#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

declare -r NODENAME="$1"
declare -r PGVER="$2"
declare -r PRIM_IP="$3"
declare -r HAPASS="$4"
declare -r LOGNODE="$5"
declare -r QNODE="$6"
shift 6
declare -r -a NODES=( "$@" )

declare -r YUM_INSTALL="yum install --nogpgcheck --quiet -y -e 0"

# detect operating system provider and version
# shellcheck disable=SC1091
source "/etc/os-release"
OS_ID="$ID"
OS_VER="$VERSION_ID"

# set hostname
hostnamectl set-hostname "${NODENAME}"

# fill /etc/hosts
for N in "${NODES[@]}"; do
    declare HNAME="${N%=*}"
    declare HIP="${N##*=}"
    if ! grep -Eq "${HNAME}\$" /etc/hosts; then
        echo "${HIP} ${HNAME}" >> /etc/hosts
    fi
done

# enable required repository
if [ "$OS_ID" = "rhel" ]; then
    # use yum instead of dnf for compatibility between EL 7 and 8
    yum-config-manager --enable "*highavailability-rpms"
elif [ "$OS_ID" = "centos" ] && [ "${OS_VER:0:1}" = "8" ]; then
    yum-config-manager --enable "HighAvailability"
fi

# install essential packages
if [ "${OS_VER:0:1}" = "8" ]; then
    $YUM_INSTALL yum-utils tmux vim policycoreutils-python-utils.noarch
else
    $YUM_INSTALL yum-utils tmux vim policycoreutils-python
fi

# SSH setup
cat <<'EOF' > "/home/vagrant/.ssh/config"
Host *
  CheckHostIP no
  StrictHostKeyChecking no
EOF

chown -R "vagrant:" "/home/vagrant/.ssh"
chmod 0700 "/home/vagrant/.ssh"
chmod 0600 "/home/vagrant/.ssh/id_rsa"
chmod 0644 "/home/vagrant/.ssh/id_rsa.pub"
chmod 0600 "/home/vagrant/.ssh/config"
chmod 0600 "/home/vagrant/.ssh/authorized_keys"

cp -R "/home/vagrant/.ssh" "/root"

# force proper permissions on .ssh files
chown -R "root:" "/root/.ssh"
chmod 0700 "/root/.ssh"
chmod 0600 "/root/.ssh/id_rsa"
chmod 0644 "/root/.ssh/id_rsa.pub"
chmod 0600 "/root/.ssh/config"
chmod 0600 "/root/.ssh/authorized_keys"

# enable firewall
systemctl --quiet --now enable firewalld

# setup log sink
if [ "$NODENAME" == "$LOGNODE" ]; then
    
    cat <<-'EOF' > /etc/rsyslog.d/log_sink.conf
	$ModLoad imtcp 
	$InputTCPServerRun 514

	$template RemoteLogsMerged,"/var/log/%HOSTNAME%/messages.log"
	*.* ?RemoteLogsMerged

	$template RemoteLogs,"/var/log/%HOSTNAME%/%PROGRAMNAME%.log"
	*.* ?RemoteLogs
	#& ~
	EOF

    if ! firewall-cmd --get-services|grep -q rsyslog-tcp; then
        firewall-cmd --quiet --permanent --new-service="rsyslog-tcp"
        firewall-cmd --quiet --permanent --service="rsyslog-tcp" --set-description="RSyslog TCP port"
        firewall-cmd --quiet --permanent --service="rsyslog-tcp" --add-port="514/tcp"
    fi
    firewall-cmd --quiet --permanent --add-service="rsyslog-tcp"
    firewall-cmd --quiet --reload

    semanage port -m -t syslogd_port_t -p tcp 514

    systemctl --quiet restart rsyslog

    exit
fi

# setting up pgsql nodes and the qnetd one

# send logs to log-sinks
cat <<'EOF' >/etc/rsyslog.d/20-fwd_log_sink.conf
*.* action(type="omfwd"
queue.type="LinkedList"
queue.filename="log_sink_fwd"
action.resumeRetryCount="-1"
queue.saveonshutdown="on"
target="log-sink" Port="514" Protocol="tcp")
EOF

systemctl --quiet restart rsyslog

# setting up pcs
$YUM_INSTALL pcs
systemctl --quiet --now enable pcsd.service
echo "$HAPASS"|passwd --stdin hacluster > /dev/null 2>&1

# setup qnetd node
if [ "$(hostname -s)" == "$QNODE" ]; then
    $YUM_INSTALL corosync-qnetd

    if ! pcs qdevice status net &>/dev/null; then
        pcs qdevice setup model net --enable --start
    fi

    firewall-cmd --quiet --permanent --add-service=high-availability
    firewall-cmd --quiet --reload

    exit
fi

# setting up pgsql nodes

# PGDG repo
if ! rpm --quiet -q "pgdg-redhat-repo"; then
    if [ "${OS_VER:0:1}" = "8" ]; then
        $YUM_INSTALL "https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm"
    else
        $YUM_INSTALL "https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm"
    fi
fi

# disable postgresql upstream module conflicting with pgdg packages in RHEL8
if [ "${OS_VER:0:1}" = "8" ]; then
    yum -qy module disable postgresql
fi

$YUM_INSTALL pacemaker corosync-qdevice    \
    resource-agents fence-agents-virsh sbd \
    perl-Module-Build                      \
    "postgresql${PGVER}"                   \
    "postgresql${PGVER}-server"            \
    "postgresql${PGVER}-contrib"

# firewall setup
firewall-cmd --quiet --permanent --add-service=high-availability
firewall-cmd --quiet --permanent --add-service=postgresql
firewall-cmd --quiet --reload

# cleanup pre-existing IP address
ip -o addr show to "${PRIM_IP}" | if grep -q "${PRIM_IP}"
then
    DEV=$(ip route show to "${PRIM_IP}/24"|grep -Eo 'dev \w+')
    ip addr del "${PRIM_IP}/24" dev "${DEV/dev }"
fi

# install PAF
cd /vagrant
[ -f Build ] && perl Build distclean
sudo -u vagrant perl Build.PL --quiet >/dev/null 2>&1
sudo -u vagrant perl Build --quiet
perl Build --quiet install

# Pcmk setup
cp /etc/sysconfig/pacemaker /etc/sysconfig/pacemaker.dist
cat<<'EOF' > /etc/sysconfig/pacemaker
PCMK_debug=yes
PCMK_logpriority=debug
EOF
