#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# install packages

PACKAGES=(
    pacemaker-cts
)

yum install --nogpgcheck --quiet -y -e 0 "${PACKAGES[@]}"

# make journald logs persistent
# other log watching methods does not look robust...
mkdir /var/log/journal
systemctl restart systemd-journald
