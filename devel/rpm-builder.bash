#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

yum --nogpgcheck --quiet -y -e 0 install git rpmdevtools perl-Module-Build resource-agents

rpmdev-setuptree
git clone --quiet https://github.com/ClusterLabs/PAF.git /root/PAF
echo silent > /etc/rpmdevtools/curlrc
spectool -R -g /root/PAF/resource-agents-paf.spec
rpmbuild --quiet -ba /root/PAF/resource-agents-paf.spec
