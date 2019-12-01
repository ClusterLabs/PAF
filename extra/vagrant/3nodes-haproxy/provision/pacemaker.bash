#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

HAPASS="$1"

# shellcheck disable=SC1091
source "/etc/os-release"
OS_ID="$ID"
YUM_INSTALL="yum install --nogpgcheck --quiet -y -e 0"

# install required packages
if [ "$OS_ID" = "rhel" ]; then
    # use yum instead of dnf for compatibility between EL 7 and 8
    yum-config-manager --enable "*highavailability-rpms"
fi

PACKAGES=(
    pacemaker pcs resource-agents fence-agents-virsh sbd perl-Module-Build
)

$YUM_INSTALL "${PACKAGES[@]}"

# install PAF
cd /vagrant
[ -f Build ] && perl Build distclean
sudo -u vagrant perl Build.PL --quiet >/dev/null 2>&1
sudo -u vagrant perl Build --quiet
perl Build --quiet install

# firewall setup
firewall-cmd --quiet --permanent --add-service=high-availability
firewall-cmd --quiet --reload

# pcsd setup
systemctl --quiet --now enable pcsd
echo "${HAPASS}"|passwd --stdin hacluster > /dev/null 2>&1

# Pacemaker setup
cp /etc/sysconfig/pacemaker /etc/sysconfig/pacemaker.dist
cat<<'EOF' > /etc/sysconfig/pacemaker
PCMK_debug=yes
PCMK_logpriority=debug
EOF
