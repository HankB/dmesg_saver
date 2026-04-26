# dmesg_saver

Save dmesg output to another host.

NB: This is heavily slanted toward Raspberry Pis running RPiOS. It can probably be used on other hosts and S/W.

## 2025-08-25 Motivation

Assist debugging by saving a copy of `dmesg -T --follow` to a disk file and then copy it to another host for viewing (and to prevent filling the disk on "small" devices.) This is driven by Raspberry Pis that seem to drop off WiFi for no obvious reason.

## 2025-08-25 Plan

Employ two scripts. 

* One that invokes `dmesg -T --follow` to a disk file after "saving" the previous record to a safe space.
* Another that copies the saved files to another host and then deletes the local copy.
* Provide Ansible playbook(s) to install Systemd units that invoke and coordinate the scripts.

## Status

* 2026-04-08 Systemd units and install playbooks remain a work in progress.
* 2026-04-05 `rpi_repartition.sh` worked once - ship it!

## 2025-08-25 Requirements

* Passwordless access to the remote host.
* A writable store for the current and saved files. (This will require a separate partition for Raspberry Pis using the `overlayfs`)
* Some configuration of the remote host to save the files.

## TODO

* 2026-04-26 Test.
* 2026-04-26 provide straightforward instructions.

## 2025-08-25 Security

There are probably security implications WRT sending a copy of `dmesg` output to another host and these should be explored before deploying this.

## 2026-04-03 Deploy

I deploy this using Ansible playbooks in a private repo at <http://oak:8080/HankB/Pi-IoT-Configuration>. It's a bit of work to move those to this repo or make my private repo public so I'll postpone effort on that unless someone wants to use this and files an issue to request that. Check that. I'm planning to move the relevant playbooks to this repo to provide a complete package.

### Repartitioning

1. Image card using `rpi-imager`
2. Perform any pre-boot customization.
3. Put card in target host and boot to perform in host initialization (including expanding the root filesystem.)
4. Stop target host, remove card and put in a host for further offline operations.
5. Run the repartitioning script.

```text
cd deploy
# identify device - most likely /dev/sdX or /dev/mmcblkN
./rpi_repartition.sh [ /dev/sdX | /dev/mmcblkN ]
```

6. Return card to target host, boot and confirm partitioning. (There should be a third `data` partition.

### install scripts and Systemd units

1. Insure that the host that runs the Ansible playubooks has passwordless SSH configured for both the target host and the storage host.
2. Execute the ansible playbook:

```text
target=<target-host-name>
storage=<storage-host-name>
ansible-playbook install-mv-dmesg.yml -i inventory -b -K \
    --extra-vars "target_host=${target} storage_host=${storage}"
```

## 2025-08-25 Future enhancements

Perhaps record various `journalctl` output instead of just `dmesg`.

## 2025-08-25 Errata

* On RpiOS `dmesg` does not require `root` so this can all be run as a normal user.
