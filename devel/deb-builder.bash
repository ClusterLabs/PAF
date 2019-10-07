#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

cd /root
DEBIAN_FRONTEND=noninteractive apt-get -qq install dh-make devscripts libmodule-build-perl resource-agents
uscan --check-dirname-level=0 --destdir=/root --force-download /vagrant
mkdir resource-agents-paf
tar zxf resource-agents-paf_*.orig.tar.gz -C "resource-agents-paf" --strip-components=1
cd resource-agents-paf
debuild --check-dirname-level=0 -i -us -uc -b
