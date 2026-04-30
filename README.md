# dmesg_saver

Save dmesg output to another host.

NB: This is heavily slanted toward Raspberry Pis running RPiOS. It can probably be used on other hosts and S/W.

## 2026-04-28 AI/LLM warning

If you object to the use of LLMs for S/W development, this effort is not for you. I used Claude to assist with `rpi_repartition.sh` and initial efforts with the Ansible playbooks. Continuing development with the playbooks was done with ChatGPT.

* I used the web page for both of these and am on the "free" plan for both. At no time did either of the LLMs have direct access to my files on my local host. At one point I asked Claude to view files in this Github repo but it was unable to due to rate limiting.
* I provided specific instructions for what I wanted to do. IMO this is not vibe coded but rather assisted with syntax and options. `rpi_repartition.sh` was significantly improved over what I would have written (and have written in other contexts.) ChatGPT led me to more sophisticated usage of Ansible than I had previously done (roles, templats.) ChatGPT also provided useful suggestions to help solve some issues I had encountered. (Coordinating mounts with Systemd by using mount units vs. cron entries.)
* I can't evaluate whether this saved me time or not, but I suspect it did. ChatGPT provided a rationale for all of its suggestions along with alternative solutions. Those helped me to learn but perhaps not as thoroughly as if I had to work out all of these things on my own (and with the helpo of web search.) Overall, I'm satisfied with my decision to leverage Claude and ChatGPT.

## 2025-08-25 Motivation

Assist debugging by saving a copy of `dmesg -T --follow` to a disk file and then copy it to another host for viewing (and to prevent filling the disk on "small" devices.) This need is driven by headless Raspberry Pis that seem to drop off WiFi for no obvious reason.

## 2025-08-25 Plan

Employ two scripts. 

* One that invokes `dmesg -T --follow` to a disk file after "saving" the previous record to a safe space.
* Another that copies the saved files to another host and then deletes the local copy.
* Provide Ansible playbook(s) to install Systemd units that invoke and coordinate the scripts.

## Status

* 2026-04-28 rewrite/reorg complete and in need of further testing and README update.
* 2026-04-27 in the midst of a massive rewrite/reorg - incomplete and may not be ready use.
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

There are more or less two steps to deploy this and they are described below in the context of a new install. For an existing RPiOS install, it is necessary to unwind `ovcerlayfs` if employed before proceeding.

### Repartitioning

1. Image card using `rpi-imager` (on a "development host")
2. Perform any pre-boot customization.
3. Put card in target host and boot to perform in host initialization (including expanding the root filesystem.)
4. Stop target host, remove card and put in a development host for further operations.
5. Run the repartitioning script.

```text
cd deploy
# identify device - most likely /dev/sdX or /dev/mmcblkN
./rpi_repartition.sh [ /dev/sdX | /dev/mmcblkN ]
```

6. Return card to target host, boot and confirm partitioning. (There should be a third `data` partition.

### install scripts and Systemd units

1. Insure that the host that runs the Ansible playbooks has passwordless SSH configured for both the target host and the storage host and that both hosts are in the `inventory` file.
2. Install `git` on the target host.
3. Insure that both target host (the one saving `dmesg` output) and storage host (where the saved output gets sent) are in the `inventory` file.
4. Execute the ansible playbook:

```text
target=<target-host-name>
storage=<storage-host-name>
ansible-playbook install-dmesg-saver.yml -i inventory -b -K \
    --extra-vars "target_host=${target} storage_host=${storage}"
```

## 2025-08-25 Future enhancements

Perhaps record various `journalctl` output instead of just `dmesg`.

## 2025-08-25 Errata

* On RpiOS `dmesg` does not require `root` so this can all be run as a normal user.
* On RPiOS when the `overalyfs` is employed, any other filesystems listed in `/etc/fstab` will also be mounted using `overalyfs`. This will cause the saved file to not be available following reboot. A cron entry to mount the filesystem does not coordinate with Systemd. A Systemd mount unit will mount the filesystem and the unit that writes to that can then wait for that before proceeding.
