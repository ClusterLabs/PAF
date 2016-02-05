# How to install this resource agent

This agent is written in perl. Its installation process follow the perl common
method, but its installation path follow usual path used for OCF libraries and
scripts.

## Prerequisite

The perl popular method to install packages use Module::Build. Depending on the
system, you might need to install a package:
  * under Debian and derivatives, you need ``libmodule-build-perl``
  * under RHEL and derivatives, you need ``perl-Module-Build``

Moreover, this module suppose you already installed Pacemaker's resource agents.
Under Debian, RHEL and their derivatives, you need the ``resource-agents``
package.


## Quick install

The quick installation process is:

```
./Build.PL
./Build
sudo ./Build install
```

This process is supposed to detect the root of your OCF files (aka. OCF_ROOT)
and install the following files in there:

  * $OCF_ROOT/lib/heartbeat/OCF_ReturnCodes.pm
  * $OCF_ROOT/lib/heartbeat/OCF_Functions.pm
  * $OCF_ROOT/lib/heartbeat/OCF_Directories.pm
  * $OCF_ROOT/resource.d/heartbeat/pgsqlms

Moreover, if the build process find an ocft config folder (usually
``/usr/share/resource-agents/ocft/configs/``), it will install the "pgsqlms"
config file in there. The ``ocft`` tool allows to run unit-tests on OCF resource
agents. See ``t/README`` for more information about it.


## Build.PL arguments

The first installation step (call of Build.PL) accept two arguments:

  * ``--with_ocf_root=PATH``: give the location of OCF_ROOT to the Build process
  * ``--with_ocft_confs=PATH``: give the location of the ocft config files

They are usually not required as Build.PL should detect their location by
itself.

## Testing

See t/README to learn more about ocft tests.
