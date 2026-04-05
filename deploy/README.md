# deploy dmesg_saver

## Overview

* Provide writable storage to hold the copy of `dmesg` output until the next boot. If this is going to be used on a Raspberry Pi that employs `overlayfs` the script `rpi_repartition.sh` can prepare this with the card available on a host that has not booted from it. Otherwise the user can provide a writable directory `/mnt/data` that is writable for the user running the scripts.
* Once prepared, run the ansible playbook(s) that
  * install the scripts
  * install Systemd units to coordinate and execute the scripts.

## `rpi_repartition.sh`

This script requires an argument naming the (unmounted) device on which the writable data partition will be created. It also creates the mount point and adds a cron entry to mount the data partition at boot. (If the partition is mounted using an entry in `/etc/fstab` and the host employs `overlayfs`, it will also be mounted using `overlayfs` and the `dmesg` record would not be preserved through reboot.)

```text
./rpi_repartition.sh /dev/somedevice
```
