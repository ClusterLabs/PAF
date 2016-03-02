---
layout: default
title: PostgreSQL Automatic Failover - Installation
---

# Installation


PostgreSQL Automatic Failover is a Pacemaker resource agent able to detect
failure on a PostgreSQL master node and trigger failover to the best existing
standby node.

This agent is written in perl. Its installation process follow the perl common
method, but its installation paths follow usual path used for OCF libraries and
scripts.

This is the manual explaining what you need to install it correctly on your
system.


## Using packages

A RPM file is available for each release. You should be able to find them on the
release page of the project hosted on github:
https://github.com/dalibo/PAF/releases

To install the lastest version of PostgreSQL Automatic Failover, go to the
following link: https://github.com/dalibo/PAF/releases/latest

Copy the link to the associated RPM file, and feed it to `yum install`. As
instances:

```
yum install https://github.com/dalibo/PAF/releases/download/v1.0.0/resource-agents-paf-1.0.0-1.noarch.rpm
```


## Installation from the sources

### Prerequisites

The perl popular method to install packages use Module::Build. Depending on the
system, you might need to install a package:

  * under Debian and derivatives, you need libmodule-build-perl
  * under RHEL and derivatives, you need perl-Module-Build

Moreover, this module suppose you already installed Pacemaker and Pacemaker's
resource agents. Under Debian, RHEL and their derivatives, you need the
`pacemaker` and `resource-agents` packages.


### Building

The lastest version of PostgreSQL Automatic Failover can be downloaded from
[https://github.com/dalibo/PAF/releases/latest](https://github.com/dalibo/PAF/releases/latest).

Unpack the source and go to the `PAF-x.y.z` folder.
To build and install the resource agent, run:

```
./Build.PL
./Build
sudo ./Build install
```

This process is supposed to detect the root of your OCF files (aka. OCF_ROOT)
and install the following files in there:

```
$OCF_ROOT/lib/heartbeat/OCF_ReturnCodes.pm
$OCF_ROOT/lib/heartbeat/OCF_Functions.pm
$OCF_ROOT/lib/heartbeat/OCF_Directories.pm
$OCF_ROOT/resource.d/heartbeat/pgsqlms
```

Moreover, if the build process find an ocft config folder (usually
`/usr/share/resource-agents/ocft/configs`), it will install the `pgsqlms`
config file in there. The ocft tool allows to run unit-tests on OCF resource
agents. See `t/README` for more information about it.

### Build arguments

The script `Build.PL` you run at the first step of the installation process
accepts two arguments:

  * `--with_ocf_root=PATH`: give the location of OCF_ROOT to the Build process
  * `--with_ocft_confs=PATH`: give the location of the ocft config files

They are usually not required as Build.PL should detect their location itself.

## Testing

See `t/README` in the source code to learn more about ocft tests.
