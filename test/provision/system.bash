#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

PGVER="$1"
HAPASS="$2"
NETWORK="$3"
MASTER_IP="$4"
DOMAIN="$5"

# install required packages
P=$(curl -s "https://download.postgresql.org/pub/repos/yum/${PGVER}/redhat/rhel-7-x86_64/"|grep -Eo "pgdg-centos[0-9.]+-${PGVER}-[0-9]+\.noarch.rpm"|head -1)

if ! rpm --quiet -q "${P/.rpm}"; then
    yum install --nogpgcheck --quiet -y -e 0 "https://download.postgresql.org/pub/repos/yum/${PGVER}/redhat/rhel-7-x86_64/$P"
fi

PACKAGES=(
    pacemaker pcs resource-agents resource-agents-paf fence-agents-virsh sbd
    "postgresql${PGVER}"
    "postgresql${PGVER}-server"
    "postgresql${PGVER}-contrib"
)

yum install --nogpgcheck --quiet -y -e 0 "${PACKAGES[@]}"

# firewall setup
systemctl enable firewalld
systemctl start  firewalld
firewall-cmd --quiet --permanent --add-service=high-availability
firewall-cmd --quiet --permanent --add-service=postgresql
firewall-cmd --quiet --reload

# cluster stuffs
systemctl enable pcsd
systemctl start  pcsd
echo "${HAPASS}"|passwd --stdin hacluster
cp /etc/sysconfig/pacemaker /etc/sysconfig/pacemaker.dist
cat<<EOF > /etc/sysconfig/pacemaker
PCMK_debug=yes
PCMK_logpriority=debug
EOF

# cleanup master ip everywhere
HAS_MASTER_IP=$(ip -o addr show to "${MASTER_IP}"|wc -l)

if [ "$HAS_MASTER_IP" -gt 0 ]; then
    DEV=$(ip route show to "${NETWORK}/24"|grep -Eom1 'dev \w+')
    ip addr del "${MASTER_IP}/24" dev "${DEV/dev }"
fi

cat <<EOF >/etc/rsyslog.d/fwd_log_sink.conf
*.* action(type="omfwd"
queue.type="LinkedList"
queue.filename="log_sink_fwd"
action.resumeRetryCount="-1"
queue.saveonshutdown="on"
target="log-sink.${DOMAIN}" Port="514" Protocol="tcp")
EOF

systemctl restart rsyslog

# remove management nameserver DNS from resolv.conf
nmcli conn modify "System eth0" ipv4.dns "" ipv4.ignore-auto-dns yes
nmcli conn up "System eth0"
