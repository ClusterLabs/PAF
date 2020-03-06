#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

YUM_INSTALL="yum install --nogpgcheck --quiet -y -e 0"

$YUM_INSTALL pcs corosync-qnetd

echo "$1"|passwd --stdin hacluster > /dev/null 2>&1

systemctl --quiet --now enable pcsd.service

if ! pcs qdevice status net cluster_pgsql|grep -q cluster_pgsql; then
    pcs qdevice setup model net --enable --start
fi

firewall-cmd --quiet --permanent --add-service=high-availability
firewall-cmd --quiet --reload
