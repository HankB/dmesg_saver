# dmesg_saver

Save dmesg output to another host.

## 2025-08-25 Motivation

Assist debugging by saving a copy of `dmesg -T --follow` to a disk file and then copy it to another host for viewing (and to prevent filling the disk on "small" devices.) This is driven by Raspberry Pis that seem to drop off WiFi for no obvious reason.

## 2025-08-25 Plan

Employ two scripts. 

* One that invokes `dmesg -T --follow` to a disk file after "saving" the previous record to a safe space.
* Another that copies the saved files to another host and then deletes the local copy.

## 2025-08-25 Requirements

* Passwordless access to the remote host.
* A writable store for the current and saved files. (This will require a separate partition for Raspberry Pis using the `overlayfs`)
* Some configuration of the remote host to save the files.

## 2025-08-25 Security

There are probably security implications WRT sending a copy of `dmesg` output to another host and these should be explored before deploying this.

## 2025-08-25 Future enhancements

Perhaps record various `journalctl` output instead of just `dmesg`.

## 2025-08-25 Errata

* On RpiOS `dmesg` does not require `root` so this can all be run as a normal user.
