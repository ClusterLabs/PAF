---
layout: default
title: PostgreSQL Automatic Failover - Installation
---

# Installation


PostgreSQL Automatic Failover is a Pacemaker resource agent able to detect
failure on a PostgreSQL primary node and trigger failover to the best existing
standby node.

This agent is written in perl. Its installation process follows the perl common
method, but its installation paths follow usual path used for OCF libraries and
scripts.

This manual explains the steps to install it correctly on your system.

Table of contents:

* [Using RPM packages](#using-rpm-packages)
* [Using Debian packages](#using-debian-packages)
* [Installation from the sources](#installation-from-the-sources)
* [Testing](#testing)


## Using RPM packages

A RPM file is available for each release. You should be able to find them on the
release page of the project hosted on github:
[https://github.com/ClusterLabs/PAF/releases](https://github.com/ClusterLabs/PAF/releases)

To install the lastest version of PostgreSQL Automatic Failover, go to the
following link:
[https://github.com/ClusterLabs/PAF/releases/latest](https://github.com/ClusterLabs/PAF/releases/latest)

Copy the link to the associated RPM file, and feed it to `yum install`. For
instance (replace `X.Y.Z` and `n` by their latest values):

```
yum install https://github.com/ClusterLabs/PAF/releases/download/vX.Y.Z/resource-agents-paf-X.Y.Z-n.noarch.rpm
```

## Using Debian packages

A Debian package is available for each release. You should be able to find them
on the release page of the project hosted on github:
[https://github.com/ClusterLabs/PAF/releases](https://github.com/ClusterLabs/PAF/releases)

To install the lastest version of PostgreSQL Automatic Failover, go to the
following link:
[https://github.com/ClusterLabs/PAF/releases/latest](https://github.com/ClusterLabs/PAF/releases/latest)

Copy the link to the associated DEB file, download it, then install it
using `dpkg`. As instance (replace `X.Y.Z` and `n` by their latest values):

```
wget 'https://github.com/ClusterLabs/PAF/releases/download/vX.Y.Z/resource-agents-paf_X.Y.Z-n_all.deb'
dpkg -i resource-agents-paf_X.Y.Z-n_all.deb
```

## Installation from the sources

### Prerequisites

The perl popular method to install packages use `Module::Build`. Depending on the
system, you might need to install a package:

  * under Debian and derivatives, you need `libmodule-build-perl`
  * under RHEL and derivatives, you need `perl-Module-Build`

Moreover, this module supposes you already installed Pacemaker and Pacemaker's
resource agents. Under Debian, RHEL and their derivatives, you need the
`pacemaker` and `resource-agents` packages.


### Building

The latest version of PostgreSQL Automatic Failover can be downloaded from
[https://github.com/ClusterLabs/PAF/releases/latest](https://github.com/ClusterLabs/PAF/releases/latest).

Unpack the source and go to the `PAF-X.Y.Z` folder. To build and install the
resource agent, run:

```
./Build.PL
./Build
sudo ./Build install
```

This process is supposed to detect the root of your OCF files (aka. `OCF_ROOT`)
and install the following files in there:

```
$OCF_ROOT/lib/heartbeat/OCF_ReturnCodes.pm
$OCF_ROOT/lib/heartbeat/OCF_Functions.pm
$OCF_ROOT/lib/heartbeat/OCF_Directories.pm
$OCF_ROOT/resource.d/heartbeat/pgsqlms
```

Moreover, if the build process find an ocft configuration folder (usually
`/usr/share/resource-agents/ocft/configs`), it will install the `pgsqlms`
configuration file in there. The ocft tool allows to run unit-tests on OCF
resource agents. See `t/README` for more information about it.

### Build arguments

The script `Build.PL` you run at the first step of the installation process
accepts two arguments:

  * `--with_ocf_root=PATH`: give the location of `OCF_ROOT` to the Build process
  * `--with_ocft_confs=PATH`: give the location of the ocft configuration files

They are usually not required as `Build.PL` should detect their location itself.

## Testing

See `t/README` in the source code to learn more about ocft tests.
