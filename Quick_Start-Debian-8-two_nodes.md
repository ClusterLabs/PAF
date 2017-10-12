---
layout: default
title: PostgreSQL Automatic Failover - Quick start Debian 8
---

# Quick Start Debian 8 - Two Nodes

This quick start tutorial is based on Debian 8.4, using the `crmsh` cluster
client and `PostgreSQL 9.6`.

The focus will be on setting up a two node cluster. The specific stuff is in 
the "Corosync" [part of this page](#corosync) and is not restricted to Debian 8.

## Repository setup

The Debian HA team missed the freeze time of Debian 8 (Jessie). They couldn't
publish the Pacemaker, Corosync and related packages on time. They did publish
them later in Debian 9 (strecth) and backport them officially for Debian 8. So
We need to setup the backport repository to install the Pacemaker stack under
Debian 8 (adapt the URL to your closest mirror):

```
cat <<EOF >> /etc/apt/sources.list.d/jessie-backports.list
deb http://ftp2.fr.debian.org/debian/ jessie-backports main
EOF
```

About PostgreSQL, this tutorial uses the PGDG repository maintained by the
PostgreSQL community (and actually Debian maintainers). Here is how to add it:

```
cat <<EOF >> /etc/apt/sources.list.d/pgdg.list
deb http://apt.postgresql.org/pub/repos/apt/ jessie-pgdg main
EOF
```

Now, update your local cache:

```
apt-get update
apt-get install pgdg-keyring
```

## Network setup

The cluster we are about to build includes two servers called `srv1` and `srv2`. 
Each of them have two network interfaces `eth1` and `eth2`. IP
addresses of these servers are `192.168.2.10x/24` on the first interface,
`192.168.3.10x/24` on the second one.

The IP address `192.168.2.100`, called `pgsql-vip` in this tutorial, will be set
on the server hosting the master PostgreSQL instance.

During the cluster setup, we use the node names in various places, make sure
all your servers names can be resolved to the correct IPs. We usually set this
in the `/etc/hosts` file:

```
cat <<EOF >> /etc/hosts
192.168.2.100 pgsql-vip
192.168.2.101 srv1
192.168.2.102 srv2
192.168.3.101 srv1-alt
192.168.3.102 srv2-alt
EOF
```

## PostgreSQL and Cluster stack installation

Let install everything we need for our cluster:

```
apt-get install -t jessie-backports pacemaker crmsh

apt-get install postgresql-9.6 postgresql-contrib-9.6 postgresql-client-9.6
```

We can now install the "PostgreSQL Automatic Failover" (PAF) resource agent:

```
wget 'https://github.com/ClusterLabs/PAF/releases/download/v2.2.0/resource-agents-paf_2.2.0-2_all.deb'
dpkg -i resource-agents-paf_2.2.0-1_all.deb
apt-get -f install
```

By default, Debian set up the instances to put the temporary activity
statistics inside a sub folder of `/var/run/postgresql/`. This sub folder is
created by the debian specific tool `pg_ctlcluster` on instance startup.

PAF only use tools provided by the PostgreSQL projects, not other specifics to
some other packages or operating system. That means that this required sub
folder set up in `stats_temp_directory` is never created and leads to error on
instance startup by Pacemaker.

To creating this sub folder on system initialization, we need to extend the
existing `systemd-tmpfiles` configuration for `postgresql` to add it. In our
environment `stats_temp_directory` is set
to `/var/run/postgresql/9.6-main.pg_stat_tmp`, so we create the following
file:

```
cat <<EOF > /etc/tmpfiles.d/postgresql-part.conf
# Directory for PostgreSQL temp stat files
d /var/run/postgresql/9.6-main.pg_stat_tmp 0700 postgres postgres - -
EOF
```

If you don't want to reboot your system to take this file in consideration,
just run the following command:

```
systemd-tmpfiles --create /etc/tmpfiles.d/postgresql-part.conf
```


## PostgreSQL setup

> **WARNING**: building PostgreSQL standby is not the main subject here. The
> following steps are __**quick and dirty**__. They lack of security, WAL
> retention and so on. Rely on the [PostgreSQL documentation](http://www.postgresql.org/docs/current/static/index.html)
> for a proper setup.
{: .warning}

The resource agent requires the PostgreSQL instances to be already set up,
ready to start and slaves ready to replicate. Make sure to setup your PostgreSQL
master on your preferred node to host the master: during the very first startup
of the cluster, PAF detects the master based on its shutdown status.

Moreover, it requires a `recovery.conf` template ready to use. You can create
a `recovery.conf` file suitable to your needs, the only requirements are:

* have `standby_mode = on`
* have `recovery_target_timeline = 'latest'`
* a `primary_conninfo` with an `application_name` set to the node name

Last but not least, make sure each instance will not be able to replicate with
itself! A scenario exists where the master IP address `pgsql-vip` will be on
the same node than a standby for a very short lap of time!

> **NOTE**: as `recovery.conf.pcmk` and `pg_hba.conf` files are different
> on each node, make sure to keep them out of the `$PGDATA` so you do not have
> to deal with them (or worst: forget to edit them) each time you rebuild a
> standby! Luckily, Debian packaging already enforce this as configuration files
> are all located in `/etc/postgresql`.
{: .notice}

Here are some quick steps to build your primary PostgreSQL instance and its
standbys. The next steps suppose the primary PostgreSQL instance is on `srv1`.

On all nodes:

```
su - postgres

cd /etc/postgresql/9.6/main/
cat <<EOP >> postgresql.conf

listen_addresses = '*'
wal_level = replica
max_wal_senders = 10
hot_standby = on
hot_standby_feedback = on
logging_collector = on
EOP

cat <<EOP >> pg_hba.conf
# forbid self-replication
host replication postgres $(hostname -s) reject
host replication postgres $(hostname -s)-alt reject

# allow any standby connection
host replication postgres 0.0.0.0/0 trust
EOP

cat <<EOP > recovery.conf.pcmk
standby_mode = on
primary_conninfo = 'host=192.168.2.100 application_name=$(hostname -s)'
recovery_target_timeline = 'latest'
EOP

exit
```

On `srv1`, the master, restart the instance and give it the master IP address:

```
systemctl restart postgresql@9.6-main

ip addr add 192.168.2.100/24 dev eth0
```

Now, on the standby (srv2), we have to cleanup the instance
created by the package and clone the primary. E.g.:

```
systemctl stop postgresql@9.6-main
su - postgres

rm -rf 9.6/main/
pg_basebackup -h pgsql-vip -D ~postgres/9.6/main/ -X stream -P

cp /etc/postgresql/9.6/main/recovery.conf.pcmk ~postgres/9.6/main/recovery.conf

exit

systemctl start postgresql@9.6-main
```

Finally, make sure to stop the PostgreSQL services __everywhere__ and to
disable them, as Pacemaker will take care of starting/stopping everything for
you. Start with your master:

```
systemctl stop postgresql@9.6-main
systemctl disable postgresql@9.6-main
echo disabled > /etc/postgresql/9.6/main/start.conf
```

And remove the master IP address from `srv1`:

```
ip addr del 192.168.2.100/24 dev eth0
```

## Cluster setup

### Pacemaker

It is advised to keep Pacemaker off on server boot. It helps the administrator
to investigate after a node fencing before Pacemaker starts and potentially
enters in a death match with the other nodes. Make sure to disable Corosync as
well to avoid unexpected behaviors. Run this on all nodes:

```
systemctl disable corosync # important!
systemctl disable pacemaker
```


### Corosync

The cluster communications and quorum (votes) rely on Corosync to work. So this
is the first service to setup to be able to build your cluster on top of it.

The cluster configuration client `crmsh` is supposed to be able to take care of
this, but this feature was broken when this tutorial was written.
See [the related bug report](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=819545).

First, stop Corosync and Pacemaker on all nodes:

```
systemctl stop corosync.service pacemaker.service
```

Here is the content of the `/etc/corosync/corosync.conf` file suitable to
the cluster as we described it so far:

```
totem {
  version: 2

  crypto_cipher: none
  crypto_hash: none

  rrp_mode: passive

  interface {
    ringnumber: 0
    bindnetaddr: 192.168.2.0
    mcastport: 5405
    ttl: 1
  }
  interface {
    ringnumber: 1
    bindnetaddr: 192.168.3.0
    mcastport: 5405
    ttl: 1
  }
  transport: udpu
}

nodelist {
  node {
    ring0_addr: srv1
    ring1_addr: srv1-alt
  }
  node {
    ring0_addr: srv2
    ring1_addr: srv2-alt
  }
}

logging {
  # to_logfile: yes
  # logfile: /var/log/corosync/corosync.log
  # timestamp: on
  to_syslog: yes
  syslog_facility: daemon
  logger_subsys {
    subsys: QUORUM
    debug: off
  }
}

quorum {
  provider: corosync_votequorum
  two_node: 1
  expected_votes: 2
  wait_for_all: 1
}
```

A few notes about the two node specific configuration:

* `two_node: 1` is requiered for two node cluster.
* `expected_votes: 2` is when two_node is chosen, but I like things to be
  explicit.
* `wait_for_all: 1` is the default with two_node. when starting from scratch,
  prevent the cluster from becoming quorate until all of the nodes have joined
  in.

For more information about this configuration file, see the `corosync.conf`
manual page. Make sure this file is strictly the same on each node.

We can now start Pacemaker on every node of the cluster:

```
systemctl start pacemaker.service
```

Here is a command to check everything is working correctly:

```
root@srv1:~# corosync-cmapctl | grep 'members.*ip'
runtime.totem.pg.mrp.srp.members.3232266853.ip (str) = r(0) ip(192.168.2.101) r(1) ip(192.168.3.101)
runtime.totem.pg.mrp.srp.members.3232266854.ip (str) = r(0) ip(192.168.2.102) r(1) ip(192.168.3.102) 
```

or

```
root@srv2:~# corosync-quorumtool 
Quorum information
------------------
Date:             Wed Jan  4 20:02:47 2017
Quorum provider:  corosync_votequorum
Nodes:            2
Node ID:          3232236134
Ring ID:          8
Quorate:          Yes

Votequorum information
----------------------
Expected votes:   2
Highest expected: 2
Total votes:      2
Quorum:           1  
Flags:            2Node Quorate WaitForAll 

Membership information
----------------------
    Nodeid      Votes Name
3232236133          1 srv1
3232236134          1 srv2 (local)
```

After some seconds of startup and cluster membership stuff, you should be able
to see your tow nodes up in `crm_mon`:

```
root@srv1:~# crm_mon -n1D
Node srv1: online
Node srv2: online
```

We can now feed this cluster with some resources to keep available. This guide
use the cluster client `crmsh` to setup everything.


## Cluster resource creation and management

First of all, let's start with some basic setup of the cluster. Run
the following command from **one** node only (the cluster takes care of
broadcasting the configuration on all nodes):

```
crm conf <<EOC
rsc_defaults resource-stickiness=10
rsc_defaults migration-threshold=5
EOC
```

In this quick start, we creates three different resources: `pgsql-ha`,
`pgsql-master-ip` and `fence_vm_xxx`.

The `pgsql-ha` resource controls all the PostgreSQL instances of your cluster
and decides where is the primary and where are the standbys.

The `pgsql-master-ip` resource controls the `pgsql-vip` IP address. It is
started on the node hosting the PostgreSQL master resource.

The last resources `fence_vm_xxx` are STONITH resources to manage fencing.
This quick start uses the `fence_virsh` fencing agent, allowing to power on or
off a virtual machine using the `virsh` command through a ssh connexion to the
hypervisor. For more information about fencing, see documentation
`docs/FENCING.md` in the source code or online:
[http://clusterlabs.github.com/PAF/fencing.html]({{ site.baseurl }}/fencing.html).

> **WARNING**: unless you build your PoC cluster using libvirt for VM
> management, there's great chances you will need to use a different STONITH
> agent. The stonith setup is provided as a simple example, be prepared to
> adjust it.
{: .warning}

Now you've been warned, let's populating the cluster with some sample STONITH
resources using virsh over ssh (`fence_virsh` fencing agent). First, we need
to allow ssh password-less authentication to `<user>@192.168.122.1` so
these fencing resource can work. Again, this is specific to this setup.
Depending on your fencing topology, you might not need this step. Run on all
node:

~~~
ssh-copy-id <user>@192.168.122.1
~~~

We can now create one STONITH resource for each node and each fencing
resource will not be allowed to run on the node it is supposed to fence.
Note that in the `port` argument of the following commands, `srv[1-3]-d8` are 
the names of the virutal machines as known by libvirtd side. See manpage 
fence_virsh(8) for more infos.

```
crm conf<<EOC
primitive fence_vm_srv1 stonith:fence_virsh                   \
  params pcmk_host_check="static-list" pcmk_host_list="srv1"  \
         ipaddr="192.168.2.1" login="<user>"                  \
         identity_file="/root/.ssh/id_rsa"                    \
         port="srv1-d8" action="off"                          \
  op monitor interval=10s
location fence_vm_srv1-avoids-srv1 fence_vm_srv1 -inf: srv1

primitive fence_vm_srv2 stonith:fence_virsh                   \
  params pcmk_host_check="static-list" pcmk_host_list="srv2"  \
         ipaddr="192.168.2.1" login="<user>"                  \
         identity_file="/root/.ssh/id_rsa"                    \
         port="srv2-d8" action="off"                          \
  op monitor interval=10s
location fence_vm_srv2-avoids-srv2 fence_vm_srv2 -inf: srv2
```

The following setup adds a bunch of resources and constraints all together in
the same time:

  1. the PostgreSQL `pgsqld` resource
  2. the multistate `pgsql-ha` responsible to clone `pgsqld` everywhere and
     define the roles (master/slave) of each clone
  3. the IP address that must be started on the PostgreSQL master node
  4. the collocation of the master IP address with the PostgreSQL master
     instance
  5. the ordering constraints between the IP address and the PostgreSQL master

```
crm conf <<EOC

# 1. resource pgsqld
primitive pgsqld pgsqlms                                                      \
  params pgdata="/var/lib/postgresql/9.6/main"                                \
         bindir="/usr/lib/postgresql/9.6/bin"                                 \
         pghost="/var/run/postgresql"                                         \
         recovery_template="/etc/postgresql/9.6/main/recovery.conf.pcmk"      \
         start_opts="-c config_file=/etc/postgresql/9.6/main/postgresql.conf" \
  op start timeout=60s                                                        \
  op stop timeout=60s                                                         \
  op promote timeout=30s                                                      \
  op demote timeout=120s                                                      \
  op monitor interval=15s timeout=10s role="Master"                           \
  op monitor interval=16s timeout=10s role="Slave"                            \
  op notify timeout=60s

# 2. resource pgsql-ha
ms pgsql-ha pgsqld meta notify=true

# 3. the master IP address
primitive pgsql-master-ip IPaddr2           \
  params ip=192.168.2.100 cidr_netmask=24 \
  op monitor interval=10s

# 4. colocation of the pgsql-ha master and the master IP address
colocation ip-with-master inf: pgsql-master-ip pgsql-ha:Master

# 5. ordering constraints
order promote-then-ip Mandatory:         \
  pgsql-ha:promote pgsql-master-ip:start \
  sequential=true symmetrical=false

order demote-then-stop-ip Mandatory:   \
  pgsql-ha:demote pgsql-master-ip:stop \
  sequential=true symmetrical=false

EOC
```

> **WARNING**: in step 5, the start/stop and promote/demote order for these
> resources must be asymetrical: we __MUST__ keep the master IP on the master
> during its demote process so the standbies receive everything during the
> master shutdown.
{: .warning}

Note that the values for `timeout` and `interval` on each operation are based
on the minimum suggested value for PAF Resource Agent.
These values should be adapted depending on the context.



