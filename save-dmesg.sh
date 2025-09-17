#!/usr/bin/env bash
# Bash3 Boilerplate. Copyright (c) 2014, kvz.io

set -o errexit
set -o pipefail
set -o nounset
############### end of Boilerplate

###########################################
#
# Save a copy of `dmesg` output
#
# typical usage is a crontab entry
#
# "@reboot /path/to/save-dmesg.sh /path/to/writable/storage
#
###########################################

# delay to insure that the writable partition is mounted
sleep 3

# Check for local destination provided on the command line

if [ $# -eq 0 ]
then
    echo "Usage: $0 /path/to/writable/storage"
    exit 1
else
    cd "$1"
    mkdir -p save
fi

# move previous dmesg output to .../save

mv -- *.txt save/    || : # ignore error
chmod a+rw -- save/* || : # ignore error

dmesg -T --follow >"dmesg.$(date +%Y-%m-%d-%H%M%S).txt"
