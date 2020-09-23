#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

declare -r NODENAME="$1"
declare -r PGVER="$2"

declare -r HAPASS="$3"
declare -r LOGNODE="$4"

shift 4
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

# setting up pgsql nodes

# send logs to log-sinks
cat <<'EOF' >/etc/rsyslog.d/20-fwd_log_sink.conf
*.* action(type="omfwd"
queue.type="LinkedList"
queue.filename="log_sink_fwd"
action.resumeRetryCount="-1"
queue.saveonshutdown="on"
target="log-sink" Port="514" Protocol="tcp")
EOF

# listen for haproxy logs locally
cat <<'EOF' >/etc/rsyslog.d/10-haproxy.conf
$ModLoad imudp
$UDPServerAddress 127.0.0.1
$UDPServerRun 514
EOF

systemctl --quiet restart rsyslog

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

$YUM_INSTALL pacemaker pcs haproxy         \
    resource-agents fence-agents-virsh sbd \
    perl-Module-Build                      \
    "postgresql${PGVER}"                   \
    "postgresql${PGVER}-server"            \
    "postgresql${PGVER}-contrib"

# setting up pcs
systemctl --quiet --now enable pcsd.service
echo "$HAPASS"|passwd --stdin hacluster > /dev/null 2>&1

# setting up haproxy
cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg-dist
cat <<'EOF' > /etc/haproxy/haproxy.cfg
global
    log         127.0.0.1:514 local2
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon

    stats socket /var/lib/haproxy/stats

defaults
    mode            tcp
    log             global
    option          tcplog
    retries         3
    timeout connect 10s
    timeout client  10m
    timeout server  10m
    timeout check   1s
    maxconn         300

listen stats
    mode http
    bind *:7000
    stats enable
    stats uri /
    timeout connect 15s
    timeout client  15s
    timeout server  15s

listen prd
    bind           *:5432
    option         tcp-check
    tcp-check      connect port 5431
    tcp-check      expect string production
    default-server inter 2s fastinter 1s rise 2 fall 1 on-marked-down shutdown-sessions
    server         srv1 srv1:5434 check
    server         srv2 srv2:5434 check
    server         srv3 srv3:5434 check

listen stb
    bind           *:5433
    balance        leastconn
    option         tcp-check
    tcp-check      connect port 5431
    tcp-check      expect string standby
    default-server inter 2s fastinter 1s rise 2 fall 1 on-marked-down shutdown-sessions
    server         srv1 srv1:5434 check
    server         srv2 srv2:5434 check
    server         srv3 srv3:5434 check
EOF

setsebool -P haproxy_connect_any=1

systemctl --quiet --now enable haproxy

# PostgreSQL state
cat<<'EOF' > /etc/systemd/system/pgsql-state@.service
[Unit]
Description=Local PostgreSQL state

[Service]
User=postgres
Group=postgres
ExecStart=/usr/pgsql-12/bin/psql -d postgres -U postgres -p 5434 -Atc "select CASE pg_is_in_recovery() WHEN true THEN 'standby' ELSE 'production' END"
StandardOutput=socket
EOF

cat<<'EOF' > /etc/systemd/system/pgsql-state.socket
[Unit]
Description=Local PostgreSQL state

[Socket]
ListenStream=5431
Accept=yes

[Install]
WantedBy=sockets.target
EOF

systemctl --quiet --now enable pgsql-state.socket

# firewall setup
firewall-cmd --quiet --permanent --service=postgresql --add-port="5433/tcp"
firewall-cmd --quiet --permanent --service=postgresql --add-port="5434/tcp"
firewall-cmd --quiet --permanent --remove-service=postgresql
firewall-cmd --quiet --permanent --add-service=postgresql
firewall-cmd --quiet --permanent --add-service=high-availability
if ! firewall-cmd --get-services|grep -q pgsql-state; then
    firewall-cmd --quiet --permanent --new-service="pgsql-state"
    firewall-cmd --quiet --permanent --service="pgsql-state" --set-description="Local PostgreSQL state"
    firewall-cmd --quiet --permanent --service="pgsql-state" --add-port="5431/tcp"
fi
firewall-cmd --quiet --permanent --add-service="pgsql-state"
if ! firewall-cmd --get-services|grep -q haproxy-stats; then
    firewall-cmd --quiet --permanent --new-service="haproxy-stats"
    firewall-cmd --quiet --permanent --service="haproxy-stats" --set-description="HAProxy statistics"
    firewall-cmd --quiet --permanent --service="haproxy-stats" --add-port="7000/tcp"
fi
firewall-cmd --quiet --permanent --add-service="haproxy-stats"
firewall-cmd --quiet --reload

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
