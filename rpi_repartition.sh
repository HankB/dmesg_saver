#!/usr/bin/env bash
# =============================================================================
# rpi_repartition.sh
# 
# Initial coding using Claude
#
# Purpose:
#   Prepare a Raspberry Pi OS (Trixie) SD card by:
#     1. Disabling overlayfs in /boot/firmware/cmdline.txt (if enabled)
#     2. Shrinking the root (ext4) partition
#     3. Creating a 1024KB ext4 data partition at the end of the card
#     4. Injecting an root cron entry to mount /mnt/data (by UUID)
#
# Usage:
#   sudo ./rpi_repartition.sh <device>
#   Example: sudo ./rpi_repartition.sh /dev/sdb
#
# Requirements:
#   - Must be run as root (or via sudo)
#   - Required tools: parted, resize2fs, e2fsck, mkfs.ext4, blkid, lsblk
#
# WARNING:
#   This script modifies partition tables and filesystems. Verify the target
#   device carefully before proceeding. Data loss is possible if the wrong
#   device is specified.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
DATA_PART_LABEL="data"
DATA_MOUNT_POINT="/mnt/data"
BOOT_FIRMWARE_SUBPATH="boot/firmware"   # relative to root partition mount
OVERLAY_TOKEN="boot=overlay"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
info()    { echo "[INFO]  $*"; }
warn()    { echo "[WARN]  $*" >&2; }
error()   { echo "[ERROR] $*" >&2; exit 1; }

require_tool() {
    command -v "$1" &>/dev/null || error "Required tool not found: $1"
}

cleanup() {
    local exit_code=$?
    info "Cleaning up mounts..."
    # Unmount in reverse order; ignore errors if already unmounted
    umount "${BOOT_MNT}" 2>/dev/null || true
    umount "${ROOT_MNT}" 2>/dev/null || true
    rm -rf "${ROOT_MNT}" "${BOOT_MNT}"
    if [[ $exit_code -ne 0 ]]; then
        warn "Script exited with errors. The SD card may be in an inconsistent state."
        warn "It is recommended to reflash before using the card."
    fi
}

# -----------------------------------------------------------------------------
# Preflight checks
# -----------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

require_tool parted
require_tool resize2fs
require_tool e2fsck
require_tool mkfs.ext4
require_tool blkid
require_tool lsblk

[[ $# -eq 1 ]] || error "Usage: $0 <device>  (e.g. $0 /dev/sdb)"
DEVICE="$1"
[[ -b "${DEVICE}" ]] || error "Not a block device: ${DEVICE}"

# Refuse to operate on a mounted device
if lsblk -no MOUNTPOINT "${DEVICE}" | grep -q .; then
    error "${DEVICE} has mounted partitions. Unmount all partitions first."
fi

# Confirm the device looks like an SD card with at least 2 partitions
PART_COUNT=$(lsblk -no NAME "${DEVICE}" | tail -n +2 | wc -l)
[[ ${PART_COUNT} -ge 2 ]] || \
    error "${DEVICE} has fewer than 2 partitions. Is this the right device?"

# Derive partition device names (handles both /dev/sdX and /dev/mmcblkX)
if [[ "${DEVICE}" =~ "mmcblk" ]]; then
    BOOT_PART="${DEVICE}p1"
    ROOT_PART="${DEVICE}p2"
else
    BOOT_PART="${DEVICE}1"
    ROOT_PART="${DEVICE}2"
fi

[[ -b "${BOOT_PART}" ]] || error "Boot partition not found: ${BOOT_PART}"
[[ -b "${ROOT_PART}" ]] || error "Root partition not found: ${ROOT_PART}"

# -----------------------------------------------------------------------------
# Safety confirmation
# -----------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  TARGET DEVICE : ${DEVICE}"
lsblk -o NAME,SIZE,FSTYPE,LABEL "${DEVICE}"
echo "============================================================"
echo ""
read -r -p "Are you sure you want to repartition ${DEVICE}? [yes/N] " CONFIRM
[[ "${CONFIRM}" == "yes" ]] || error "Aborted by user."

# -----------------------------------------------------------------------------
# Set up temp mount points and cleanup trap
# -----------------------------------------------------------------------------
ROOT_MNT=$(mktemp -d /tmp/rpi_root_XXXXXX)
BOOT_MNT=$(mktemp -d /tmp/rpi_boot_XXXXXX)
trap cleanup EXIT

# -----------------------------------------------------------------------------
# Step 1: Disable overlayfs in cmdline.txt
# -----------------------------------------------------------------------------
info "Mounting root partition read-write to check overlayfs..."
mount "${ROOT_PART}" "${ROOT_MNT}"

CMDLINE_PATH="${ROOT_MNT}/${BOOT_FIRMWARE_SUBPATH}/cmdline.txt"

# Boot partition may be a separate vfat partition; mount it too
info "Mounting boot partition..."
mount "${BOOT_PART}" "${ROOT_MNT}/${BOOT_FIRMWARE_SUBPATH}"

if [[ ! -f "${CMDLINE_PATH}" ]]; then
    warn "cmdline.txt not found at ${CMDLINE_PATH} — skipping overlayfs check."
else
    if grep -q "${OVERLAY_TOKEN}" "${CMDLINE_PATH}"; then
        info "overlayfs detected. Removing '${OVERLAY_TOKEN}' from cmdline.txt..."
        # cmdline.txt is a single line; use sed to remove the token in-place
        sed -i "s| ${OVERLAY_TOKEN}||g; s|${OVERLAY_TOKEN} ||g; s|${OVERLAY_TOKEN}||g" \
            "${CMDLINE_PATH}"
        info "overlayfs disabled. Verify cmdline.txt:"
        cat "${CMDLINE_PATH}"
    else
        info "overlayfs not detected in cmdline.txt. Nothing to change."
    fi
fi

info "Unmounting partitions before filesystem operations..."
umount "${ROOT_MNT}/${BOOT_FIRMWARE_SUBPATH}"
umount "${ROOT_MNT}"

# -----------------------------------------------------------------------------
# Step 2: Check and shrink the root filesystem
# -----------------------------------------------------------------------------
info "Running e2fsck on root partition (${ROOT_PART})..."
# e2fsck returns non-zero on corrections; allow exit codes 0 and 1
e2fsck -f -y "${ROOT_PART}" || {
    RC=$?
    [[ $RC -le 1 ]] || error "e2fsck returned error code ${RC}. Inspect ${ROOT_PART} manually."
}

info "Shrinking root filesystem to minimum size..."
resize2fs -M "${ROOT_PART}"

# Determine the new minimum size in 512-byte sectors
ROOT_BLOCK_SIZE=$(tune2fs -l "${ROOT_PART}" | awk '/^Block size:/ {print $3}')
ROOT_BLOCK_COUNT=$(tune2fs -l "${ROOT_PART}" | awk '/^Block count:/ {print $3}')
ROOT_FS_BYTES=$(( ROOT_BLOCK_SIZE * ROOT_BLOCK_COUNT ))
# Add 5% overhead to avoid tight fit issues, round up to nearest MB
ROOT_FS_MB=$(( (ROOT_FS_BYTES * 105 / 100 / 1024 / 1024) + 1 ))
info "Root filesystem shrunk. New target partition size: ${ROOT_FS_MB} MiB (includes 5% overhead)"

# -----------------------------------------------------------------------------
# Step 2b: Verify filesystem size is consistent with partition size
#
# If a previous run shrunk the filesystem but aborted before resizing the
# partition, the filesystem will be smaller than its containing partition.
# This is safe but we detect and report it so the user knows the state.
# If the filesystem is somehow *larger* than the partition, that is a serious
# inconsistency and we refuse to proceed.
# -----------------------------------------------------------------------------
info "Checking filesystem/partition size consistency..."

# Filesystem size already known from ROOT_FS_BYTES above.
# Partition size in bytes (from parted).
PART_SIZE_BYTES=$(parted -s "${DEVICE}" unit B print \
    | awk '/^ *2 / {gsub(/B/,""); print $4}')

info "  Filesystem size : $(( ROOT_FS_BYTES / 1024 / 1024 )) MiB  (${ROOT_FS_BYTES} bytes)"
info "  Partition size  : $(( PART_SIZE_BYTES / 1024 / 1024 )) MiB  (${PART_SIZE_BYTES} bytes)"

if (( ROOT_FS_BYTES > PART_SIZE_BYTES )); then
    error "Filesystem is LARGER than its partition. This is a serious inconsistency. Inspect ${ROOT_PART} manually before proceeding."
elif (( ROOT_FS_BYTES < PART_SIZE_BYTES )); then
    warn "Filesystem is smaller than its partition (likely from a previous partial run)."
    warn "This is safe — the script will proceed to resize the partition to match."
else
    info "Filesystem and partition sizes are consistent."
fi

# -----------------------------------------------------------------------------
# Step 3: Repartition — shrink root, add data partition
# -----------------------------------------------------------------------------
info "Reading current partition layout..."
DISK_SIZE_MB=$(parted -s "${DEVICE}" unit MiB print \
    | awk '/^Disk \/dev/ {gsub(/MiB/,""); print $3}')
info "Total disk size: ${DISK_SIZE_MB} MiB"

DATA_PART_SIZE_MB=1   # 512KB rounds up to 1 MiB as parted minimum alignment unit
DATA_START_MB=$(( DISK_SIZE_MB - DATA_PART_SIZE_MB ))
ROOT_END_MB=${DATA_START_MB}

info "Shrinking root partition to ${ROOT_END_MB} MiB..."
# Get the start of partition 2 so we can recreate it at the same start point.
ROOT_PART_START=$(parted -s "${DEVICE}" unit MiB print \
    | awk '/^ *2 / {gsub(/MiB/,""); print $2}')
info "  Root partition starts at ${ROOT_PART_START} MiB"
# Delete and recreate partition 2 at the new (smaller) end boundary.
# This avoids parted's interactive "data loss" prompt that resizepart triggers
# and that cannot be reliably suppressed across parted versions.
parted -s "${DEVICE}" rm 2
parted -s "${DEVICE}" mkpart primary ext4 "${ROOT_PART_START}MiB" "${ROOT_END_MB}MiB"

info "Creating data partition (${DATA_PART_SIZE_MB} MiB at end of disk)..."
parted -s "${DEVICE}" mkpart primary ext4 "${DATA_START_MB}MiB" "100%"

# Refresh partition table
partprobe "${DEVICE}" 2>/dev/null || true
sleep 2

# Derive data partition device name
if [[ "${DEVICE}" =~ "mmcblk" ]]; then
    DATA_PART="${DEVICE}p3"
else
    DATA_PART="${DEVICE}3"
fi
[[ -b "${DATA_PART}" ]] || error "Data partition not found after partitioning: ${DATA_PART}"

# -----------------------------------------------------------------------------
# Step 4: Format data partition
# -----------------------------------------------------------------------------
info "Formatting data partition as ext4 with label '${DATA_PART_LABEL}'..."
mkfs.ext4 -L "${DATA_PART_LABEL}" "${DATA_PART}"

DATA_UUID=$(blkid -s UUID -o value "${DATA_PART}")
info "Data partition UUID: ${DATA_UUID}"

# -----------------------------------------------------------------------------
# Step 5: Resize root filesystem to fill its (now smaller) partition
# -----------------------------------------------------------------------------
info "Expanding root filesystem to fill shrunk partition..."
e2fsck -f -y "${ROOT_PART}" || true
resize2fs "${ROOT_PART}"

# -----------------------------------------------------------------------------
# Step 6: Injecting an root cron entry to mount /mnt/data (by UUID)
# -----------------------------------------------------------------------------
info "Mounting root partition to update /etc/fstab..."
mount "${ROOT_PART}" "${ROOT_MNT}"

CRON_FILE="${ROOT_MNT}/etc/cron.d/mount_mnt_data"
info "Creating cron entry to mount /mnt/data in ${CRON_FILE}"

echo "@reboot root /bin/mount -t ext4  UUID=${DATA_UUID}  ${DATA_MOUNT_POINT} && /bin/chmod a+rwx ${DATA_MOUNT_POINT}"  > "${CRON_FILE}" 

# Create the mount point directory on the root filesystem
MOUNT_DIR="${ROOT_MNT}${DATA_MOUNT_POINT}"
if [[ ! -d "${MOUNT_DIR}" ]]; then
    info "Creating mount point directory ${DATA_MOUNT_POINT} on root fs..."
    mkdir -p "${MOUNT_DIR}"

fi

info "Unmounting root partition..."
umount "${ROOT_MNT}"

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  rpi_repartition.sh completed successfully."
echo ""
echo "  Root partition : ${ROOT_PART}"
echo "  Data partition : ${DATA_PART}  (UUID: ${DATA_UUID})"
echo "  Mount point    : ${DATA_MOUNT_POINT}"
echo "  overlayfs      : disabled"
echo ""
echo "  The card is ready to be returned to the Pi."
echo "  overlayfs can be re-enabled via raspi-config once the"
echo "  installation is stable."
echo "============================================================"