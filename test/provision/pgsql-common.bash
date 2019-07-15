#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

PGVER="$1"
HAPASS="$2"
MASTER_IP="$3"

YUM_INSTALL="yum install --nogpgcheck --quiet -y -e 0"

# install required packages
if ! rpm --quiet -q "pgdg-redhat-repo"; then
    $YUM_INSTALL "https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm"
fi

PACKAGES=(
    pacemaker pcs resource-agents fence-agents-virsh sbd perl-Module-Build
    "postgresql${PGVER}"
    "postgresql${PGVER}-server"
    "postgresql${PGVER}-contrib"
)

$YUM_INSTALL "${PACKAGES[@]}"

# firewall setup
systemctl --quiet --now enable firewalld
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

# install PAF
cd /home/vagrant/PAF/
perl Build.PL --quiet >/dev/null 2>&1
perl Build --quiet install
