#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# install packages

PACKAGES=(
    pacemaker-cts patch
)

yum install --nogpgcheck --quiet -y -e 0 "${PACKAGES[@]}"

# fix bug in the log watcher.
patch /usr/lib64/python2.7/site-packages/cts/watcher.py ~vagrant/watcher.py.diff

# do not drop any log messages from rsyslog
cat <<'EOF'>/etc/rsyslog.d/rateLimit.conf
$imjournalRatelimitInterval 0
$imjournalRatelimitBurst 0
EOF

systemctl --quiet restart rsyslog

# make journald logs persistent
mkdir -p /var/log/journal

# do not drop any log messages from journald
mkdir -p /etc/systemd/journald.conf.d
cat <<'EOF'>/etc/systemd/journald.conf.d/rateLimit.conf
RateLimitInterval=0
RateLimitBurst=0
EOF

systemctl --quiet restart systemd-journald
