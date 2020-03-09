#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

yum --nogpgcheck --quiet -y -e 0 install git rpmdevtools perl-Module-Build resource-agents rpmlint

rpmdev-setuptree

rpmlint /vagrant/resource-agents-paf.spec
cd /vagrant
TAG=$(awk '/^%global _tag/{print $NF}' /vagrant/resource-agents-paf.spec)
git archive --prefix="PAF-${TAG}/" --format=tar.gz v${TAG} > /root/rpmbuild/SOURCES/v${TAG}.tar.gz
rpmbuild --quiet -ba /vagrant/resource-agents-paf.spec
rpmlint /root/rpmbuild/RPMS/noarch/resource-agents-paf-*.noarch.rpm
