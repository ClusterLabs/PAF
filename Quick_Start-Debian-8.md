---
layout: default
title: PostgreSQL Automatic Failover - Quick start Debian 8
---

# Quick Start Debian 8

This quick start tutorial is based on Debian 8.4, using the `crm` cluster
client.

## Repository setup

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

The cluster we are about to build include three servers called `srv1`, `srv2`
and `srv3`. Each of them have two network interfaces `eth0` and `eth1`. IP
addresses of these servers are `192.168.122.10x/24` on the first interface,
`192.168.123.10x/24` on the second one.

The IP address `192.168.122.100`, called `pgsql-ha` in this tutorial, will be set
on the server hosting the master PostgreSQL instance.

During the cluster setup, we use the node names in various places, make sure
all your servers names can be resolved to the correct IPs. We usually set this
in the `/etc/hosts` file: 

```
cat <<EOF >> /etc/hosts
192.168.122.100 pgsql-ha
192.168.122.101 srv1
192.168.122.102 srv2
192.168.122.103 srv3
192.168.123.101 srv1-alt
192.168.123.102 srv2-alt
192.168.123.103 srv3-alt
EOF
```

## PostgreSQL and Cluster stack installation

Let install everything we need for our cluster:

```
apt-get install -t jessie-backports pacemaker crmsh

apt-get install postgresql-9.3 postgresql-contrib-9.3 postgresql-client-9.3 git
```

Finally, we need to install the `pgsql-resource-agent` resource agent:

```
cd /usr/local/src
git clone https://github.com/dalibo/PAF.git
cd pgsql-resource-agent/
perl Build.PL
./Build
./Build install
```

## PostgreSQL setup

The resource agent requires the PostgreSQL instances to be already set up and
ready to start. Moreover, it requires a `recovery.conf` template ready to use.
You can create a `recovery.conf` file suitable to your needs, the only
requirements are:

  * have `standby_mode = on`
  * have `recovery_target_timeline = 'latest'`
  * a `primary_conninfo` with an `application_name` set to the node name

Here are some quick steps to build your primary postgres instance and its
standbies. As this is not the main subject here, they are
__**quick and dirty**__. Rely on the PostgreSQL documentation for a proper
setup.

The next steps suppose the primary instance is on srv1.

On all nodes:

```
su - postgres

cd /etc/postgresql/9.3/main/
cat <<EOP >> postgresql.conf

listen_addresses = '*'
wal_level = hot_standby
max_wal_senders = 10
hot_standby = on
hot_standby_feedback = on
EOP

cat <<EOP >> pg_hba.conf
# forbid self-replication
host replication postgres 192.168.122.100/32 reject
host replication postgres $(hostname -s) reject

# allow any standby connection
host replication postgres 0.0.0.0/0 trust
EOP

cat <<EOP > recovery.conf.pcmk
standby_mode = on
primary_conninfo = 'host=192.168.122.100 application_name=$(hostname -s)'
recovery_target_timeline = 'latest'
EOP

exit
```

On srv1, the master, restart the instance and give it the master IP address:

```
systemctl restart postgresql@9.3-main

ip addr add 192.168.122.100/24 dev eth0
```

Now, on each standby (srv2 and srv3 here), we have to cleanup the instance
created by the package and clone the primary. E.g.:

```
systemctl stop postgresql@9.3-main
su - postgres

rm -rf 9.3/main/
pg_basebackup -h pgsql-ha -D ~postgres/9.3/main/ -X stream -P

cp /etc/postgresql/9.3/main/recovery.conf.pcmk ~postgres/9.3/main/recovery.conf

exit

systemctl start postgresql@9.3-main
```

Finally, make sure to stop the PostgreSQL services __everywhere__ and to
disabling them, as Pacemaker will take care of starting/stopping everything for
you. Start with your master:

```
systemctl stop postgresql@9.3-main
systemctl disable postgresql@9.3-main
```

And remove the master IP address from `srv1`:

```
ip addr del 192.168.122.100/24 dev eth0
```

## Cluster setup

### Corosync

The cluster communications and quorum (votes) rely on Corosync to work. So this
is the first service to setup to be able to build your cluster on top of it.

The cluster configuration client `crm` is supposed to be able to take care of
this, but this feature was broken when this tutorial was written (See
https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=819545).

So here is the content of the `/etc/corosync/corosync.conf` file suitable to
the cluster as we described it so far:

```
totem {
  version: 2
  
  crypto_cipher: none
  crypto_hash: none

  rrp_mode: passive
  
  interface {
    ringnumber: 0
    bindnetaddr: 192.168.122.0
    mcastport: 5405
    ttl: 1
  }
  interface {
    ringnumber: 1
    bindnetaddr: 192.168.123.0
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
  node {
    ring0_addr: srv3
    ring1_addr: srv3-alt
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
  expected_votes: 3
}
```

For more information about this configuration file, see the `corosync.conf`
manual page.

We can now start corosync:

```
systemctl start corosync.service

```

Here is a command to check everything is working correctly:

```
root@srv1:~# corosync-cmapctl | grep 'members.*ip'
runtime.totem.pg.mrp.srp.members.3232266853.ip (str) = r(0) ip(192.168.122.101) r(1) ip(192.168.123.101) 
runtime.totem.pg.mrp.srp.members.3232266854.ip (str) = r(0) ip(192.168.122.102) r(1) ip(192.168.123.102) 
runtime.totem.pg.mrp.srp.members.3232266855.ip (str) = r(0) ip(192.168.122.103) r(1) ip(192.168.123.103) 
```

### Pacemaker

It is advised to keep Pacemaker off on server boot. It helps the administrator
to investigate after a node fencing before Pacemaker start and potentially
enter in a death match as instance. Run this on all nodes:


```
systemctl disable pacemaker
```

We can now start it manually on all node:


```
systemctl start pacemaker
```

After some seconds of startup and cluster membership stuff, you should be able
to see your three node up in `crm_mon`:

```
root@srv1:~# crm_mon -n1D
Node srv1: online
Node srv2: online
Node srv3: online
```

We can now feed this cluster with some resource to keep available. This guide
use the cluster client `crm` to setup everything.

## Cluster resource creation and management

This setup create three different resources: `pgsql-ha`, `pgsql-master-ip`
and `fence_vm_xxx`.

The `pgsql-ha` resource represent all the PostgreSQL instances of your cluster
and control where is the primary and who are the standbys. The
`pgsql-master-ip` is located on the node hosting the postgres master. The last
resources `fence_vm_xxx` are stonith resource: we create one stonith
resource for each node. Each fencing resource will not be allowed to run on the
node it is suppose to stop. We are using the fence_vm stonith agent, which is
power fencing agent allowing to power on or off a virtual machine through the
`virsh` command. For more information about fencing, see documentation
`docs/FENCING.md` in the source code or online:
[http://dalibo.github.com/PAF/fencing.html]({{ site.baseurl }}/fencing.html).

First of all, let's start with some basic setup of the cluster:

```
crm conf <<EOC
property default-resource-stickiness=10
property migration-limit=3
property no-quorum-policy=ignore
EOC
```

Then, we must start populating it with the stonith resources:

```
crm conf<<EOC             
primitive fence_vm_srv1 stonith:fence_virsh                   \
  params pcmk_host_check="static-list" pcmk_host_list="srv1"  \
         ipaddr="192.168.122.1" login="ioguix"                \
         identity_file="/root/.ssh/id_rsa"                    \
         port="srv1-d8" action="off"                          \
  op monitor interval=10s
location fence_vm_srv1-avoids-srv1 fence_vm_srv1 -inf: srv1

primitive fence_vm_srv2 stonith:fence_virsh                   \
  params pcmk_host_check="static-list" pcmk_host_list="srv2"  \
         ipaddr="192.168.122.1" login="ioguix"                \
         identity_file="/root/.ssh/id_rsa"                    \
         port="srv2-d8" action="off"                          \
  op monitor interval=10s
location fence_vm_srv2-avoids-srv2 fence_vm_srv2 -inf: srv2

primitive fence_vm_srv3 stonith:fence_virsh                   \
  params pcmk_host_check="static-list" pcmk_host_list="srv3"  \
         ipaddr="192.168.122.1" login="ioguix"                \
         identity_file="/root/.ssh/id_rsa"                    \
         port="srv3-d8" action="off"                          \
  op monitor interval=10s
location fence_vm_srv3-avoids-srv3 fence_vm_srv3 -inf: srv3
EOC
```

The following setup adds a bunch of resources and constraints all together in
the same time:
  1. the PostgreSQL `pgsqld` resource
  2. the multistate `pgsql-ha` responsible to clone `pgsqld` everywhere and
     define the roles (master/slave) of each clone
  3. the IP address that must be start on the PostgreSQL master node
  4. the collocation of the master IP address with the PostgreSQL master
     instance
  5. the preference about where the master should be start. As we defined
     earlier, our master is supposed to be on srv1

```
crm conf <<EOC

# 1. resource pgsqld
primitive pgsqld pgsqlms                                                      \
  params pgdata="/var/lib/postgresql/9.3/main"                                \
         bindir="/usr/lib/postgresql/9.3/bin"                                 \
         pghost="/var/run/postgresql"                                         \
         recovery_template="/etc/postgresql/9.3/main/recovery.conf.pcmk"      \
         start_opts="-c config_file=/etc/postgresql/9.3/main/postgresql.conf" \
  op monitor role="Master" interval=9s                                        \
  op monitor role="Slave"  interval=10s

# 2. resource pgsql-ha
ms pgsql-ha pgsqld                          \
  meta master-max=1 master-node-max=1       \
  clone-max=3 clone-node-max=1 notify=true

# 3. the master IP address
primitive pgsql-master-ip IPaddr2           \
  params ip=192.168.122.100 cidr_netmask=24 \
  op monitor interval=10s

# 4. colocation of the pgsql-ha master and the master IP address
colocation ip-with-master inf: pgsql-master-ip pgsql-ha:Master

order promote-then-ip Mandatory:         \
  pgsql-ha:promote pgsql-master-ip:start \
  sequential=true symmetrical=false

order stop-ip-then-demote Mandatory:   \
  pgsql-ha:demote pgsql-master-ip:stop \
  sequential=true symmetrical=false

# 5. location preference for the pgsql-ha master
location pgsql-ha_master-prefers-srv1 pgsql-ha role=Master 1: srv1

EOC
```

About the collocation between `pgsql-ha` and `pgsql-master-ip`, note that the
start/stop and promote/demote order for these resource is asymetrical: we
__must__ keep the master IP on the master during its demote process.



