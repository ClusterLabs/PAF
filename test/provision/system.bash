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

# force proper permissions on .ssh files
chmod -R 0600 /root/.ssh/
