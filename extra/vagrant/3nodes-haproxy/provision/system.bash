#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

NODENAME="$1"
RHEL_USER="$2"
RHEL_PASS="$3"
shift 3
NODES=( "$@" )

hostnamectl set-hostname "${NODENAME}"

for N in "${NODES[@]}"; do
    NG=$(sed -n "/${N%=*}\$/p" /etc/hosts|wc -l)
    if [ "$NG" -eq 0 ]; then
        echo "${N##*=} ${N%=*}" >> /etc/hosts
    fi
done

# shellcheck disable=SC1091
source "/etc/os-release"
OS_ID="$ID"
YUM_INSTALL="yum install --nogpgcheck --quiet -y -e 0"

PACKAGES=( vim bash-completion yum-utils policycoreutils policycoreutils-python )

if [ "$OS_ID" = "rhel" ]; then
    subscription-manager register --force --username "${RHEL_USER:?}" --password "${RHEL_PASS:?}" --auto-attach
    PACKAGES+=("tmux")
else
    PACKAGES+=("screen")
fi

$YUM_INSTALL "${PACKAGES[@]}"

cat <<'EOF' > "/home/vagrant/.ssh/config"
Host *
  CheckHostIP no
  StrictHostKeyChecking no
EOF

cp "/vagrant/extra/vagrant/3nodes-haproxy/provision/id_rsa" "/home/vagrant/.ssh"
cp "/vagrant/extra/vagrant/3nodes-haproxy/provision/id_rsa.pub" "/home/vagrant/.ssh"

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
