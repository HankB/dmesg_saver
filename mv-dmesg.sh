#!/usr/bin/env bash
# Bash3 Boilerplate. Copyright (c) 2014, kvz.io

set -o errexit
set -o pipefail
set -o nounset
############### end of Boilerplate

###########################################
#
# move previously saved dmesg output to a remote host
# and delete the local copy
#
# typical usage is a crontab entry
#
# "@reboot /path/to/mv-dmesg.sh /local/storage remote:/path/to/remote/storage
#
###########################################

# Check for local storage and remote storage provided on the command line

if [ $# -le 1 ]
then
    echo "Usage: $0 /path/to/dmesg/storage remote:/remote/storage"
    exit 1
else
    cd "$1"
    remote="$2"
fi

# delay for WiFi startup
# delay to allow 'save-dmesg.sh' to save files to /local/storage

sleep 15

for i in *
do
    echo "sending $i to $remote"
    scp "$i" "$remote" && rm "$i"
done