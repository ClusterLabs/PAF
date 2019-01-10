#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# setup log sink
cat <<'EOF' > /etc/rsyslog.d/log_sink.conf
$ModLoad imtcp 
$InputTCPServerRun 514

$template RemoteLogsMerged,"/var/log/%HOSTNAME%/messages.log"
*.* ?RemoteLogsMerged

$template RemoteLogs,"/var/log/%HOSTNAME%/%PROGRAMNAME%.log"
*.* ?RemoteLogs
& ~
EOF

systemctl restart rsyslog

# install packages

PACKAGES=(
    screen vim
)

yum install --nogpgcheck --quiet -y -e 0 "${PACKAGES[@]}"

# remove management nameserver DNS from resolv.conf
nmcli conn modify "System eth0" ipv4.dns "" ipv4.ignore-auto-dns yes
nmcli conn up "System eth0"

# allow passwordless ssh connections between nodes as root.
cat ~root/.ssh/id_rsa.pub >> ~root/.ssh/authorized_keys

