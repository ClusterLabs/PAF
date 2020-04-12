---
layout: default
title: PostgreSQL Automatic Failover - Configuration
---

# Configuration

PostgreSQL Automatic Failover agent is a Pacemaker's multi-state resource
agent, developped using the OCF specification. As such, it allows several
parameters to be set during the configuration process.

Please note that we assume you are already familiar with both Pacemaker and
PostgreSQL installation and configuration. In consequence, we only describe in
this section the PAF related parameters.


## PostgreSQL configuration

Before configuring the resource agent, PostgreSQL must be installed on all the
nodes it is supposed to run on, and be propertly configured to allow streaming
replication between nodes.

For more details about how to configure streaming replication with PostgreSQL,
please refer to the
[official documentation](http://www.postgresql.org/docs/current/static/index.html).

With PostgreSQL 11 and before, it requires a template of the `recovery.conf` file ready
to use on __all the nodes__. You have to know that every single PostgreSQL instance will
be started as a standby before one of them is picked by Pacemaker to be promoted as the
master. Moreover, your cluster will move with switchovers, failovers, upgrade, etc. In
short, each node should be able to be a standby. You can create such a template file
suitable to your needs, the only requirements are:

  * have `standby_mode = on`
  * have `recovery_target_timeline = 'latest'`
  * a `primary_conninfo` with an `application_name` set to the node name

If you are using PostgreSQL 12 and after, you don't need this template file. Just set the
`primary_conninfo` parameter in the main configuration file. Note the
`recovery_target_timeline` parameter is already set to `latest` by default.

Moreover, if you rely on Pacemaker to move an IP resource on the node hosting
the master role of PostgreSQL, make sure to add rules on the `pg_hba.conf` file
of each instance to forbid self-replication.

It is advised to put all these setups outside the `$PGDATA` to ease the procedure to
rebuild standby without having to edit configuration files. Use `include` family
parameters and eg. `hba_file`.

Last but not least, during the very first startup of your cluster, the
designated master will be the only instance stopped gently as a primary. Take
great care of this when you setup your cluster for the first time


## PAF resource configuration

These parameters are used by the agent to propertly manage the PostgreSQL
resource.
They are usually set up during the resource creation process.

For more information about how to create and configure a multi-state resource
with Pacemaker, please refer to
[the project's official documentation](http://clusterlabs.org/doc/).

### Resource agent parameters

These parameters are specific to the PAF resource agent, and usually should be
modified depending on the specificities of your installation.

  * `system_user` : System user account used to run the PostgreSQL server
    * default value `postgres`
  * `bindir`: Path to the directory storing the PostgreSQL binaries. The agent
    uses `psql`, `pg_isready`, `pg_controldata` and `pg_ctl`.
    * default value: `/usr/bin`
  * `pgdata`: Path to the data directory of the managed PostgreSQL instance,
    e.g. `PGDATA`
    * default value: `/var/lib/pgsql/data`
  * `datadir`: Path to the directory set in data_directory from your postgresql.conf file. This parameter
    has the same default than PostgreSQL itself: the pgdata parameter value. Unless you have a
    special PostgreSQL setup and you understand this parameter, ignore it.
    * default value: `$PGDATA`
  * `pghost`: Local host IP address or unix socket folder the instance is
    listening on.
    * default value: `/tmp`
  * `pgport`: Port the instance is listening on.
    * default value: `5432`
  * `recovery_template`: Path to the `recovery.conf` template for PostgreSQL 11 and
    before. This file is simply copied by Pacemaker to `$PGDATA` under the
    `recovery.conf` name before it starts the instance as a slave resource. From
    PostgreSQL 12 and after, the resource agent raise an error if the file exists.
    * default value: `$PGDATA/recovery.conf.pcmk`
  * `start_opts`: Additionnal arguments given to the postgres process on
    startup.
    See `postgres --help` for available options. Usefull when the
    `postgresql.conf` file is not in the data directory (`PGDATA`), eg.:
    `-c config_file=/etc/postgresql/9.3/main/postgresql.conf`.
  * `maxlag`: Maximum lag allowed on a standby before we set a negative master
     score on it. The calculation is based on the difference between the current xlog 
     location on the master and the write location on the standby.
     This parameter must be a valid positive number as described in PostgreSQL documentation.
     See: https://www.postgresql.org/docs/current/static/sql-syntax-lexical.html#SQL-SYNTAX-CONSTANTS-NUMERIC
    * default value: `0` (disabled)


### Resource agent actions

When creating a resource, one can (and should) specify several optionnal
parameters for every action the resource agent supports.
This section lists the actions supported by the PAF resource agent, and the
minimum suggested value.

They are by no mean the default values, so when configuring the resource you
should always explicitely specify the values that fit your context.
If you don't know what values to chose, the ones mentionned here are a good
value to start with.

Please note that these actions are for the internal use of Pacemaker only, and
it will use every value you configure here (like how much time it has to wait
before deciding a resource has failed to stop, and fence the node instead).

  * action `monitor` with parameter `role` set to `Master` (mandatory):
    check done regularly (based on the `interval` parameter's value) on the
    local resource, it determines how fast a problem will be detected on the
    master resource (primary PostgreSQL instance)
    * parameter `interval` suggested value: `15s`
    * parameter `timeout` suggested value: `10s`
  * action `monitor` with parameter `role` set to `Slave` (mandatory):
    check done regularly (based on the `interval` parameter's value) on the
    local resource, it determines how fast a problem will be detected on a
    slave resource (standby PostgreSQL instance)
    * parameter `interval` suggested value: `16s` (you __must__ chose a 
      different value from the master resource monitor action)
    * parameter timeout suggested value: `10s`
  * action `start`: start the local PostgreSQL instance
    * parameter `timeout` suggested value: `60s`
  * action `stop`: stop the local PostgreSQL instance
    * parameter `timeout` suggested value: `60s`
  * action `promote`: promote a slave resource as a master (and thus, promote
    the related standby PostgreSQL instance to a primary role)
    * parameter `timeout` suggested value: `30s`
  * action `demote`: demote a master resource as a slave (within PAF code,
    this is implemented by stopping the primary PostgreSQL instance, and
    starting it again as a standby, thus its timeout should at least be equal
    to the sum of the ones of `stop` and `start` actions)
    * parameter `timeout` suggested value: `120s`
  * action `notify`: executed at the same time on several nodes of the cluster
    before and after each actions. This is important in PAF mechanism.
    * parameter timeout suggested value: `60s`

### Multi-state resource parameters

After creating your PostgreSQL resource in previous chapter, you need to
create the specific master/slave resource tht will clone the previous resource
on several nodes, using two different states, `master` and `slave`.

Here are the parameter for such resources:

  * `master-max`: number of PostgreSQL resources that can be set as primary at
    a given time. The only meaningful value here is `1`, do not set it to
    anything else. If not given, the default value is `1`.
  * `clone-max`: maximum number of nodes allowed to run a PostgreSQL resource,
    primary or standby. If not given, the default value is the number of node in
    the cluster.
  * `clone-node-max`: maximum number of PostgreSQL resources that can run _on a
    single node_. The only meaningful value here is `1`, do not set it to
    anything else. If not given, the default value is `1`.
  * `notify=true`: enable action `notify` for the resource. You must enable it
    explicitly as this action is disabled by default. This is mandatory
    as the resource agent rely heavily on this action.


## Other considerations

Creating a working Pacemaker's cluster will usually involves much more
configuration than just the PostgreSQL instances and resources.
For example, having a Pacemaker's managed IP that is always up on the master
PostgreSQL resource seems like a good idea. And obviously, you also have to
configure [fencing]({{ site.baseurl }}/fencing.html).

This additionnal configuration steps are out of the scope of this document, so
you should refer to the
[official Pacemaker's documentation](http://clusterlabs.org/doc/).


## Full examples

See the Quick starts for full examples of cluster, resource creation and
configuration:

* [CentOS 6]({{ site.baseurl }}/Quick_Start-CentOS-6.html)
* [CentOS 7]({{ site.baseurl }}/Quick_Start-CentOS-7.html)
* [CentOS 8]({{ site.baseurl }}/Quick_Start-CentOS-8.html)
* [Debian 8]({{ site.baseurl }}/Quick_Start-Debian-8.html)
* [Debian 9]({{ site.baseurl }}/Quick_Start-Debian-9-crm.html)

## Cookbooks

Somes cookbooks are aailable to help you manage your cluster. See:

* [Cookbook for CentOS 7]({{ site.baseurl }}/CentOS-7-admin-cookbook.html) (using `pcs`)
* [Cookbook for Debian 8]({{ site.baseurl }}/Debian-8-admin-cookbook.html) (using `crm`)

