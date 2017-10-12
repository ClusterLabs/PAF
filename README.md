# PostgreSQL Automatic Failover

High-Availibility for Postgres, based on industry references Pacemaker and
Corosync.

## Description

Pacemaker is nowadays the industry reference for High Availability. In the same
fashion than for Systemd, all Linux distributions moved (or are moving) to this
unique Pacemaker+Corosync stack, removing all other existing high availability
stacks (CMAN, RGManager, OpenAIS, ...). It is able to detect failure on various
services and automatically decide to failover the failing resource to another
node when possible.

To be able to manage a specific service resource, Pacemaker interact with it
through a so-called "Resource Agent". Resource agents must comply to the OCF
specification which define what they must implement (start, stop, promote,
etc), how they should behave and inform Pacemaker of their results.

PostgreSQL Automatic Failover is a new OCF resource Agent dedicated to
PostgreSQL. Its original wish is to keep a clear limit between the Pacemaker
administration and the PostgreSQL one, to keep things simple, documented and
yet powerful.

Once your PostgreSQL cluster built using internal streaming replication, PAF is
able to expose to Pacemaker what is the current status of the PostgreSQL
instance on each node: master, slave, stopped, catching up, etc. Should a
failure occurs on the master, Pacemaker will try to recover it by default.
Should the failure be non-recoverable, PAF allows the slaves to be able to
elect the best of them (the closest one to the old master) and promote it as
the new master. All of this thanks to the robust, feature-full and most
importantly experienced project: Pacemaker.

For information about how to install this agent, see `INSTALL.md`.

## Setup and requirements

PAF supports PostgreSQL 9.3 and higher. It has been extensively tested under
CentOS 6 and 7 in various scenario.

PAF has been written to give to the administrator the maximum control
over their PostgreSQL configuration and architecture. Thus, you are 100%
responsible for the master/slave creations and their setup. The agent
will NOT edit your setup. It only requires you to follow these pre-requisites:

  * slave __must__ be in hot_standby (accept read-only connections)
  * you __must__ provide a template file on each node which will be copied as
    the local `recovery.conf` when needed by the agent
  * the recovery template file __must__ contain `standby_mode = on`
  * the recovery template file __must__ contain `recovery_target_timeline = 'latest'`
  * the `primary_conninfo` parameter in the recovery template file __must__
    set the `application_name` to the node name as seen in Pacemaker
    (usually, the hostname)

When setting up the resource in Pacemaker, here are the available parameters you
can set:

  * `bindir`: location of the PostgreSQL binaries (default: `/usr/bin`)
  * `pgdata`: location of the PGDATA of your instance (default:
    `/var/lib/pgsql/data`)
  * `datadir`: path to the directory set in `data_directory` from your
    postgresql.conf file. This parameter has same default than PostgreSQL
    itself: the `pgdata` parameter value. Unless you have a special PostgreSQL
    setup and you understand this parameter, __ignore it__
  * `pghost`: the socket directory or IP address to use to connect to the
    local instance (default: `/tmp`)
  * `pgport`:  the port to connect to the local instance (default: `5432`)
  * `recovery_template`: the local template that will be copied as the
    `PGDATA/recovery.conf` file. This template file must exists on all node
    (default: `$PGDATA/recovery.conf.pcmk`)
  * `start_opts`: Additional arguments given to the postgres process on startup.
    See "postgres --help" for available options. Useful when the postgresql.conf
    file is not in the data directory (PGDATA), eg.:
    `-c config_file=/etc/postgresql/9.3/main/postgresql.conf`
  * `system_user`: the system owner of your instance's process (default:
    `postgres`)
  * `maxlag`: maximum lag allowed on a standby before we set a negative master
     score on it. The calculation is based on the difference between the current
     xlog location on the master and the write location on the standby.
     (default: 0, which disables this feature)

For a demonstration about how to setup a cluster, see
[http://clusterlabs.github.io/PAF/documentation.html](http://clusterlabs.github.io/PAF/documentation.html).

