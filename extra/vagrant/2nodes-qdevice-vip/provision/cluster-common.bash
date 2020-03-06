#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

PGVER="$1"
HAPASS="$2"
MASTER_IP="$3"

# shellcheck disable=SC1091
source "/etc/os-release"
OS_ID="$ID"
OS_VER="$VERSION_ID"
YUM_INSTALL="yum install --nogpgcheck --quiet -y -e 0"

# install required packages
if [ "$OS_ID" = "rhel" ]; then
    # use yum instead of dnf for compatibility between EL 7 and 8
    yum-config-manager --enable "*highavailability-rpms"
fi

if ! rpm --quiet -q "pgdg-redhat-repo"; then
    if [ "${OS_VER:0:2}" = "8." ]; then
        $YUM_INSTALL "https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm"
    else
        $YUM_INSTALL "https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm"
    fi
fi

# disable postgresql upstream module conflicting with pgdg packages in RHEL8
if [ "${OS_VER:0:2}" = "8." ]; then
    yum -qy module disable postgresql
fi

PACKAGES=(
    pacemaker corosync-qdevice pcs resource-agents fence-agents-virsh sbd perl-Module-Build
    "postgresql${PGVER}"
    "postgresql${PGVER}-server"
    "postgresql${PGVER}-contrib"
)

$YUM_INSTALL "${PACKAGES[@]}"

# firewall setup
firewall-cmd --quiet --permanent --add-service=high-availability
firewall-cmd --quiet --permanent --add-service=postgresql
firewall-cmd --quiet --reload

# cluster stuffs
systemctl --quiet --now enable pcsd
echo "${HAPASS}"|passwd --stdin hacluster > /dev/null 2>&1
cp /etc/sysconfig/pacemaker /etc/sysconfig/pacemaker.dist
cat<<'EOF' > /etc/sysconfig/pacemaker
PCMK_debug=yes
PCMK_logpriority=debug
EOF

# cleanup master ip everywhere
HAS_MASTER_IP=$(ip -o addr show to "${MASTER_IP}"|wc -l)

if [ "$HAS_MASTER_IP" -gt 0 ]; then
    DEV=$(ip route show to "${MASTER_IP}/24"|grep -Eom1 'dev \w+')
    ip addr del "${MASTER_IP}/24" dev "${DEV/dev }"
fi

# send logs to log-sinks
cat <<'EOF' >/etc/rsyslog.d/fwd_log_sink.conf
*.* action(type="omfwd"
queue.type="LinkedList"
queue.filename="log_sink_fwd"
action.resumeRetryCount="-1"
queue.saveonshutdown="on"
target="log-sink" Port="514" Protocol="tcp")
EOF

systemctl --quiet restart rsyslog

# cleanup pre-existing IP address
ip -o addr show to "${MASTER_IP}" | if grep -q "${MASTER_IP}"
then
    DEV=$(ip route show to "${MASTER_IP}/24"|grep -Eo 'dev \w+')
    ip addr del "${MASTER_IP}/24" dev "${DEV/dev }"
fi

# install PAF
cd /vagrant
[ -f Build ] && perl Build distclean
sudo -u vagrant perl Build.PL --quiet >/dev/null 2>&1
sudo -u vagrant perl Build --quiet
perl Build --quiet install
