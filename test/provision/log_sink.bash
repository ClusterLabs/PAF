#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

DOMAIN="$1"

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
