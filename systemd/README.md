# dmesg_saver Systemd units

Two unit files coordinate and kick off execution.

## `save-dmesg.service`

This unit waits for NTP time sync before it starts recording so that the timestamp for the resulting file as well as the time stamps for entries are correct. When this condition is met and it has moved the previous file to `/mnt/data/save` it will "notify" so that `mv-dmesg.sh` can move the previous record to the storage host.

```text
systemctl status save-dmesg.service
journalctl -b -u save-dmesg.service
systemctl status systemd-time-wait-sync.service
```

## `mv-dmesg.service`

This unit waits for `save-dmesg.service` to `notify` that the previous record has been moved and is ready to be sent to the storage host.

```text
systemctl status mv-dmesg.service
```

