---
layout: default
title: PostgreSQL Automatic Failover - Quick start CentOS 7
---

# Quick Start CentOS 7

This quick start tutorial is based on CentOS 7.2, using the `pcs` command.

* [Network setup](#network-setup)
* [PostgreSQL and Cluster stack installation](#postgresql-and-cluster-stack-installation)
* [PostgreSQL setup](#postgresql-setup)
* [Cluster pre-requisites](#cluster-pre-requisites)
* [Cluster creation](#cluster-creation)
* [Node fencing](#node-fencing)
* [Cluster resources](#cluster-resources)
* [Conclusion](#conclusion)

## Network setup

The cluster we are about to build includes three servers called `srv1`,
`srv2` and `srv3`. Each of them have two network interfaces `eth0` and
`eth1`. IP addresses of these servers are `192.168.122.5x/24` on the first
interface, `192.168.123.5x/24` on the second one.

The IP address `192.168.122.50`, called `pgsql-vip` in this tutorial, will be
set on the server hosting the master PostgreSQL instance.

Considering the firewall, we have to allow the network traffic related to the
cluster and PostgreSQL to go through:

~~~
firewall-cmd --permanent --add-service=high-availability
firewall-cmd --add-service=high-availability
firewall-cmd --permanent --add-service=postgresql
firewall-cmd --add-service=postgresql
~~~

During the cluster setup, we use the node names in various places,
make sure all your server hostnames can be resolved to the correct IPs. We
usually set this in the `/etc/hosts` file:

~~~
192.168.122.50 pgsql-vip
192.168.122.51 srv1
192.168.122.52 srv2
192.168.122.53 srv3
192.168.123.51 srv1-alt
192.168.123.52 srv2-alt
192.168.123.53 srv3-alt
~~~

Now, the three servers should be able to ping each others, eg.:

~~~
root@srv1:~# for s in srv1 srv2 srv3; do ping -W1 -c1 $s; done| grep icmp_seq
64 bytes from srv1 (192.168.122.51): icmp_seq=1 ttl=64 time=0.028 ms
64 bytes from srv2 (192.168.122.52): icmp_seq=1 ttl=64 time=0.296 ms
64 bytes from srv3 (192.168.122.53): icmp_seq=1 ttl=64 time=0.351 ms
~~~


## PostgreSQL and Cluster stack installation

Run this whole chapter on ALL nodes.

We are using the PostgreSQL packages from the PGDG repository. Here is how to
install and set up this repository on your system:

~~~
yum install -y http://yum.postgresql.org/9.6/redhat/rhel-7-x86_64/pgdg-centos96-9.6-3.noarch.rpm
~~~

Make sure to double adapt the previous command with the latest package available
and the PostgreSQL version you need.

We can now install everything we need for our cluster:

~~~
yum install -y postgresql96 postgresql96-contrib postgresql96-server \
               pacemaker resource-agents resource-agents-paf pcs     \
               fence-agents-all fence-agents-virsh
~~~


## PostgreSQL setup

> **WARNING**: building PostgreSQL standby is not the main subject here. The
> following steps are __**quick and dirty, VERY DIRTY**__. They lack of
> security, WAL retention and so on. Rely on the [PostgreSQL documentation](http://www.postgresql.org/docs/current/static/index.html)
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

> **WARNING**: as `recovery.conf.pcmk` and `pg_hba.conf` files are different
> on each node, it is best to keep them out of the `$PGDATA` so you do not have
> to deal with them (or worst: forget to edit them) each time you rebuild a
> standby! We advice you to deal with this using the `hba_file` parameter in
> your `postgresql.conf` file and `recovery_template` parameter in PAF for the
> `recovery.conf.pcmk` file.
{: .warning}

Here are some quick steps to build your primary PostgreSQL instance and its
standbys. This quick start considers `srv1` is the preferred master.

On the primary:

~~~
/usr/pgsql-9.6/bin/postgresql96-setup initdb

su - postgres

cd 9.6/data/
cat <<EOP >> postgresql.conf

listen_addresses = '*'
wal_level = replica
max_wal_senders = 10
hot_standby = on
hot_standby_feedback = on
EOP

cat <<EOP >> pg_hba.conf
# forbid self-replication
host replication postgres 192.168.122.50/32 reject
host replication postgres $(hostname -s) reject

# allow any standby connection
host replication postgres 0.0.0.0/0 trust
EOP

cat <<EOP > recovery.conf.pcmk
standby_mode = on
primary_conninfo = 'host=192.168.122.50 application_name=$(hostname -s)'
recovery_target_timeline = 'latest'
EOP

exit

systemctl start postgresql-9.6
ip addr add 192.168.122.50/24 dev eth0
~~~

Now, on each standby, clone the primary. E.g.:

~~~
su - postgres

pg_basebackup -h pgsql-vip -D ~postgres/9.6/data/ -X stream -P

cd ~postgres/9.6/data/

sed -ri s/srv[0-9]+/$(hostname -s)/ pg_hba.conf
sed -ri s/srv[0-9]+/$(hostname -s)/ recovery.conf.pcmk

cp recovery.conf.pcmk recovery.conf

exit

systemctl start postgresql-9.6
~~~

Finally, make sure to stop the PostgreSQL services __everywhere__ and to
disable them, as Pacemaker will take care of starting/stopping everything for
you during cluster normal cluster operations:

~~~
systemctl stop postgresql-9.6
systemctl disable postgresql-9.6
~~~

And remove the master IP address from `srv1`:

~~~
ip addr del 192.168.122.50/24 dev eth0
~~~


## Cluster pre-requisites

It is advised to keep Pacemaker off on server boot. It helps the administrator
to investigate after a node fencing before Pacemaker starts and potentially
enters in a death match with the other nodes. Make sure to disable Corosync as
well to avoid unexpected behaviors. Run this on all nodes:

~~~
systemctl disable corosync # important!
systemctl disable pacemaker
~~~


This guide uses the cluster management tool `pcsd` provided by RHEL to ease the
creation and setup of a cluster. It allows to create the cluster from command
line, without editing configuration files or XML by hands.

`pcsd` uses the `hacluster` system user to work and communicate with other
members of the cluster. We need to set a password to this user so it can
authenticate to other nodes easily. As cluster management commands can be run on
any member of the cluster, it is recommended to set the same password everywhere
to avoid confusions:

~~~
passwd hacluster
~~~

Enable and start the `pcsd` daemon on all the nodes:

~~~
systemctl enable pcsd
systemctl start pcsd
~~~

Now, authenticate each node to the other ones using the following command:

~~~
pcs cluster auth srv1 srv2 srv3 -u hacluster
~~~


## Cluster creation

The `pcs` cli tool is able to create and start the whole cluster for us. From
one of the nodes, run the following command:

~~~
pcs cluster setup --name cluster_pgsql srv1,srv1-alt srv2,srv2-alt srv3,srv3-alt
~~~

> **NOTE**: If you don't have an alternative network available use the
> following syntax instead of the previous one:
>
> ~~~
> pcs cluster setup --name cluster_pgsql srv1 srv2 srv3
> ~~~
>
> Make sure you have a redundant network at system level. This is a
> __**CRITICAL**__ part of your cluster.
{: .notice}

This command creates the `/etc/corosync/corosync.conf` file and propagate
it everywhere. For more information about it, read the `corosync.conf(5)`
manual page.

> **WARNING**: whatever you edit in your `/etc/corosync/corosync.conf` file,
> __**ALWAYS**__ make sure all the nodes in your cluster has the exact same
> copy of the file.
{: .warning}

You can now start the whole cluster from one node:

~~~
pcs cluster start --all
~~~

After some seconds of startup and cluster membership stuff, you should be able
to see your three nodes up in `crm_mon` (or `pcs status`):

~~~
root@srv1:~# crm_mon -n1D
Node srv1: online
Node srv2: online
Node srv3: online
~~~

Now the cluster run, let's start with some basic setup of the cluster. Run
the following command from **one** node only (the cluster takes care of
broadcasting the configuration on all nodes):

~~~
pcs resource defaults migration-threshold=5
pcs resource defaults resource-stickiness=10
~~~

This sets two default values for resources we create in the next chapter:

* `resource-stickiness`: adds a sticky score for the resource on its current
  node. It helps avoiding a resource move back and forth between nodes where it
  has the same score.
* `migration-threshold`: this controls how many time the cluster tries to
  recover a resource on the same node before moving it on another one.


## Node fencing

One of the most important resource in your cluster is the one able to fence a
node. Please, stop reading this quick start and read our fencing
documentation page before building your cluster. Take a deep breath, and open
`docs/FENCING.md` in the source code of PAF or read online:
[http://clusterlabs.github.com/PAF/fencing.html]({{ site.baseurl }}/fencing.html).

> **WARNING**: I really mean it. You need fencing. PAF is expecting fencing to
> work in your cluster. Without fencing, you will experience cluster refusing
> to move anything, even with stonith disabled, or worst, a split brain if you
> bend it hard enough to make it work anyway.
> If you don't mind taking time rebuilding a database with corrupt and/or
> incoherent data and constraints, that's fine though.
{: .warning}

In this tutorial, we choose to create one fencing resource per node to fence.
They are called `fence_vm_xxx`and use the fencing agent `fence_virsh`, allowing
to power on or off a virtual machine using the `virsh` command through a ssh
connexion to the hypervisor.

> **WARNING**: unless you build your PoC cluster using libvirt for VM
> management, there's great chances you will need to use a different STONITH
> agent. The stonith setup is provided as a simple example, be prepared to
> adjust it.
{: .warning}

Now you've been warned again and again, let's populating the cluster with some
sample STONITH resources using virsh over ssh. First, we need to allow ssh
password-less authentication to `<user>@192.168.122.1` so these fencing
resource can work. Again, this is specific to this setup. Depending on your
fencing topology, you might not need this step. Run on all node:

~~~
ssh-keygen
ssh-copy-id <user>@192.168.122.1
~~~

Check the ssh connections are working as expected.

We can now create one STONITH resource for each node. Each fencing
resource will not be allowed to run on the node it is supposed to fence.
Note that in the `port` argument of the following commands, `srv[1-3]-c7` are
the names of the virutal machines as known by libvirtd side. See manpage
fence_virsh(8) for more infos.

~~~
pcs cluster cib cluster1.xml
pcs -f cluster1.xml stonith create fence_vm_srv1 fence_virsh \
  pcmk_host_check="static-list" pcmk_host_list="srv1"        \
  ipaddr="192.168.122.1" login="<user>" port="srv1-c7"       \
  identity_file="/root/.ssh/id_rsa"

pcs -f cluster1.xml stonith create fence_vm_srv2 fence_virsh \
  pcmk_host_check="static-list" pcmk_host_list="srv2"        \
  ipaddr="192.168.122.1" login="<user>" port="srv2-c7"       \
  identity_file="/root/.ssh/id_rsa"

pcs -f cluster1.xml stonith create fence_vm_srv3 fence_virsh \
  pcmk_host_check="static-list" pcmk_host_list="srv3"        \
  ipaddr="192.168.122.1" login="<user>" port="srv3-c7"       \
  identity_file="/root/.ssh/id_rsa"

pcs -f cluster1.xml constraint location fence_vm_srv1 avoids srv1=INFINITY
pcs -f cluster1.xml constraint location fence_vm_srv2 avoids srv2=INFINITY
pcs -f cluster1.xml constraint location fence_vm_srv3 avoids srv3=INFINITY
pcs cluster cib-push cluster1.xml
~~~

Using `crm_mon` You should see the three resources appearing in your cluster
and being dispatched on nodes.


## Cluster resources

In this last chapter we create three resources: `pgsqld`, `pgsql-ha`,
and `pgsql-master-ip`.

The `pgsqld` defines the properties of a PostgreSQL instance: where it is
located, where are its binaries, its configuration files, how to montor it, and
so on.

The `pgsql-ha` resource controls all the PostgreSQL instances `pgsqld` in your
cluster, decides where the primary is promoted and where the standbys
are started.

The `pgsql-master-ip` resource controls the `pgsql-vip` IP address. It is
started on the node hosting the PostgreSQL master resource.

Now the fencing is working, we can add all other resources and constraints all
together in the same time. Create a new offline CIB:

~~~
pcs cluster cib cluster1.xml
~~~

We add the PostgreSQL `pgsqld` resource and the multistate `pgsql-ha`
responsible to clone it everywhere and define the roles (master/slave) of each
clone:

~~~
# pgsqld
pcs -f cluster1.xml resource create pgsqld ocf:heartbeat:pgsqlms \
    bindir=/usr/pgsql-9.6/bin pgdata=/var/lib/pgsql/9.6/data     \
    op start timeout=60s                                         \
    op stop timeout=60s                                          \
    op promote timeout=30s                                       \
    op demote timeout=120s                                       \
    op monitor interval=15s timeout=10s role="Master"            \
    op monitor interval=16s timeout=10s role="Slave"             \
    op notify timeout=60s

# pgsql-ha
pcs -f cluster1.xml resource master pgsql-ha pgsqld notify=true
~~~

Note that the values for `timeout` and `interval` on each operation are based
on the minimum suggested value for PAF Resource Agent. These values should be
adapted depending on the context.

We add the IP address which should be started on the primary node:

~~~
pcs -f cluster1.xml resource create pgsql-master-ip ocf:heartbeat:IPaddr2 \
    ip=192.168.122.50 cidr_netmask=24 op monitor interval=10s
~~~

We now define the collocation between `pgsql-ha` and `pgsql-master-ip`. The
start/stop and promote/demote order for these resources must be asymetrical: we
__MUST__ keep the master IP on the master during its demote process so the
standbies receive everything during the master shutdown.

~~~
pcs -f cluster1.xml constraint colocation add pgsql-master-ip with master pgsql-ha INFINITY
pcs -f cluster1.xml constraint order promote pgsql-ha then start pgsql-master-ip symmetrical=false kind=Mandatory
pcs -f cluster1.xml constraint order demote pgsql-ha then stop pgsql-master-ip symmetrical=false kind=Mandatory
~~~

We can now push our CIB to the cluster, which will start all the magic stuff:

~~~
pcs cluster cib-push cluster1.xml
~~~


## Conclusion

Now you know the basics to build a Pacemaker cluster hosting some PostgreSQL
instance replicating with each others, you should probably check:

* [how to set up properly the PostgreSQL replication](https://www.postgresql.org/docs/current/static/high-availability.html)
* this quick start show you how to implement network redundancy in Corosync,
  but it best fits in the operating system layer. Documentation about how to
  setup network bonding or teaming are popular on internet.
* have a look at our basic
  [administration cookbooks for CentOS 7 using pcs]({{ site.baseurl}}/CentOS-7-admin-cookbook.html).
