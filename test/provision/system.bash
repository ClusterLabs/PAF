#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

NODENAME="$1"
shift
NODES=( "$@" )

hostnamectl set-hostname "${NODENAME}"

for N in "${NODES[@]}"; do
    NG=$(sed -n "/${N%=*}\$/p" /etc/hosts|wc -l)
    if [ "$NG" -eq 0 ]; then
        echo "${N##*=} ${N%=*}" >> /etc/hosts
    fi
done

PACKAGES=(
    screen vim bash-completion
)

yum install --nogpgcheck --quiet -y -e 0 "${PACKAGES[@]}"

cat <<'EOF' > "/home/vagrant/.ssh/config"
Host *
  CheckHostIP no
  StrictHostKeyChecking no
EOF

cp "/home/vagrant/PAF/test/provision/id_rsa" "/home/vagrant/.ssh"
cp "/home/vagrant/PAF/test/provision/id_rsa.pub" "/home/vagrant/.ssh"

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
