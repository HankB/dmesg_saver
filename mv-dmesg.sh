#!/usr/bin/env bash
# Bash3 Boilerplate. Copyright (c) 2014, kvz.io

set -o errexit
set -o pipefail
set -o nounset
############### end of Boilerplate

###########################################
#
# Move previously saved dmesg output to a remote host
# and delete the local copies.
#
# Intended to run as a oneshot systemd service after network-online.target.
#
# Usage:
#   mv-dmesg.sh /local/storage remote-host:/path/to/remote/storage
#
# Example:
#   mv-dmesg.sh /mnt/data/save storage-host:/mnt/dmesg/IoT/ryugu/
#
# Requirements:
#   - Passwordless SSH access to the remote host
#   - Remote destination directory must already exist
#
###########################################

if [ $# -ne 2 ]; then
    echo "Usage: $0 /path/to/local/storage remote-host:/path/to/remote/storage"
    exit 1
fi

local_storage="$1"
remote="$2"

# Verify local storage directory exists and is accessible
if [ ! -d "${local_storage}" ]; then
    echo "Error: local storage directory '${local_storage}' does not exist"
    exit 1
fi

cd "${local_storage}"

# Check for files to send — exit cleanly if none
shopt -s nullglob
files=( *.txt )
shopt -u nullglob

if [ ${#files[@]} -eq 0 ]; then
    echo "No files to send in ${local_storage}"
    exit 0
fi

for f in "${files[@]}"; do
    echo "Sending ${f} to ${remote}"
    scp "${f}" "${remote}" && rm "${f}"
done
