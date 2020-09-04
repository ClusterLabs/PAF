---
layout: default
title: PostgreSQL Automatic Failover - Quick start Debian 10 using pcs
---

# Quick Start Debian 10 using pcs

This quick start purpose is to help you to build your first cluster to
experiment with. It does *not* implement various good practices related to
your system, Pacemaker or PostgreSQL. This quick start alone is not enough.
During your journey in building a safe HA cluster, you must train about
security, network, PostgreSQL, Pacemaker, PAF, etc.
In regard with PAF, make sure to read carefully documentation from
<https://clusterlabs.github.io/PAF/documentation.html>.

This tutorial is based on Debian 10.5, using Pacemaker 2.0.1, `pcs` version
0.10.1 and PostgreSQL 12.

Table of contents:

* [Repository setup](#repository-setup)
* [Network setup](#network-setup)
* [PostgreSQL and Cluster stack installation](#postgresql-and-cluster-stack-installation)
* [PostgreSQL setup](#postgresql-setup)
* [Cluster pre-requisites](#cluster-pre-requisites)
* [Cluster creation](#cluster-creation)
* [Node fencing](#node-fencing)
* [Cluster resources](#cluster-resources)
* [Conclusion](#conclusion)


## Repository setup

To install PAF and PostgreSQL, this tutorial uses the PGDG repository maintained
by the PostgreSQL community (and actually Debian maintainers). Here is how to
add it:

~~~
cat <<EOF >> /etc/apt/sources.list.d/pgdg.list
deb https://apt.postgresql.org/pub/repos/apt/ buster-pgdg main
EOF
~~~

Now, update your local apt cache:

~~~
apt install ca-certificates gpg
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add
apt update
apt install pgdg-keyring
~~~


## Network setup

The cluster we are about to build includes three servers called `srv1`,
`srv2` and `srv3`. IP addresses of these servers are `192.168.122.7x/24`.

> **NOTE**: It is essential to setup network redundancy, either at
> system level using eg. bonding or teaming, or at cluster level.
{: .notice}

The IP address `192.168.122.70`, called `pgsql-vip` in this tutorial, will be
set on the server hosting the primary PostgreSQL instance.

During the cluster setup, we use the node names in various places,
make sure all your server hostnames can be resolved to the correct IPs. We
usually set this in the `/etc/hosts` file:

~~~
192.168.122.70 pgsql-vip
192.168.122.71 srv1
192.168.122.72 srv2
192.168.122.73 srv3
~~~

Now, the three servers should be able to ping each others, eg.:

~~~
root@srv1:~# for s in srv1 srv2 srv3; do ping -W1 -c1 $s; done| grep icmp_seq
64 bytes from srv1 (192.168.122.71): icmp_seq=1 ttl=64 time=0.028 ms
64 bytes from srv2 (192.168.122.72): icmp_seq=1 ttl=64 time=0.296 ms
64 bytes from srv3 (192.168.122.73): icmp_seq=1 ttl=64 time=0.351 ms
~~~

Make sure hostnames are correctly set on each nodes, or use `hostnamectl`.
Eg.:

~~~bash
hostnamectl set-hostname srv1
~~~


## PostgreSQL and Cluster stack installation

Run this whole chapter on __ALL__ nodes.

Let's install everything we need: PostgreSQL, Pacemaker, cluster related
packages and PAF:

~~~bash
apt install --no-install-recommends pacemaker pacemaker-cli-utils fence-agents pcs
apt install postgresql-12 postgresql-contrib-12 postgresql-client-12
apt install resource-agents-paf
~~~

We add the `--no-install-recommends` because the apt tools are setup by default
to install all recommended packages in addition to the usual dependencies. This
might be fine in most case, but we want to keep this quick start small, easy
and clear. Installing recommended packages requires some more attention on
other subjects not related to this document (eg. setting up some IPMI daemon).

By default, Debian set up the instances to put the temporary activity
statistics inside a sub folder of `/var/run/postgresql/`. This sub folder is
created by the debian specific tool `pg_ctlcluster` on instance startup.

PAF only use tools provided by the PostgreSQL projects, no other ones specifics
to some other packages or operating system. That means that this required sub
folder set up in `stats_temp_directory` is never created and leads to error on
instance startup by Pacemaker.

To create this sub folder on system initialization, we need to extend the
existing `systemd-tmpfiles` configuration for `postgresql` to add it. In our
environment `stats_temp_directory` is set
to `/var/run/postgresql/12-main.pg_stat_tmp`, so we create the following
file:

~~~bash
cat <<EOF > /etc/tmpfiles.d/postgresql-part.conf
# Directory for PostgreSQL temp stat files
d /run/postgresql/12-main.pg_stat_tmp 0700 postgres postgres - -
EOF
~~~

To take this file in consideration immediately without rebooting the server,
run the following command:

~~~bash
systemd-tmpfiles --create /etc/tmpfiles.d/postgresql-part.conf
~~~

Lastly, during Pacemaker and Corosync installation, Debian packaging
automatically creates and start a dummy isolated node. We need to move it out
of our way by destroying it before creating the real one:

~~~bash
pcs cluster destroy
~~~


## PostgreSQL setup

> **WARNING**: building PostgreSQL standby is not the main subject here. The
> following steps are __**quick and dirty, VERY DIRTY**__. They lack of
> security, WAL retention and so on. Rely on the
> [PostgreSQL documentation](http://www.postgresql.org/docs/current/static/index.html)
> for a proper setup.
{: .warning}

The resource agent requires the PostgreSQL instances to be already set up,
ready to start and standbys ready to replicate. Make sure to setup your primary
on your preferred node to host it: during the very first startup of the
cluster, PAF detects the primary based on its shutdown status.

PostgreSQL configuration need:

* `recovery_target_timeline = 'latest'`, which is already the default value.
* a `primary_conninfo` with an `application_name` set to the node name

Last but not least, make sure each instance is not able to replicate with
itself! A scenario exists where the primary IP address `pgsql-vip` will be on
the same node than a standby for a very short lap of time!

> **NOTE**: as PostgreSQL configuration files are different
> on each node, make sure to keep them out of the `$PGDATA` so you do not have
> to deal with them (or worst: forget to edit them) each time you rebuild a
> standby! Luckily, Debian packaging already enforce this as configuration files
> are all located in `/etc/postgresql`.
{: .notice}

Here are some quick steps to build your primary PostgreSQL instance and its
standbys. This quick start considers `srv1` is the preferred primary node.

On all nodes:

~~~bash
su - postgres

cd /etc/postgresql/12/main/
cat <<EOP >> postgresql.conf

listen_addresses = '*'
hot_standby_feedback = on
logging_collector = on
primary_conninfo = 'host=192.168.122.70 application_name=$(hostname -s)'
EOP

cat <<EOP >> pg_hba.conf
# forbid self-replication
host replication postgres 192.168.122.70/32 reject
host replication postgres $(hostname -s) reject

# allow any standby connection
host replication postgres 0.0.0.0/0 trust
EOP

exit
~~~

On `srv1`, the primary, restart the instance and give it the primary vIP address
(adapt the `eth0` interface to your system):

~~~bash
systemctl restart postgresql@12-main

ip addr add 192.168.122.70/24 dev eth0
~~~

Now, on each standby (`srv2` and `srv3` here), we have to cleanup the instance
created by the package and clone the primary. E.g.:

~~~bash
systemctl stop postgresql@12-main
su - postgres

rm -rf 12/main/
pg_basebackup -h pgsql-vip -D ~postgres/12/main/ -X stream -P

touch ~postgres/12/main/standby.signal

exit

systemctl start postgresql@12-main
~~~

Check your three instances are replicating as expected (in processes, logs,
`pg_stat_replication`, etc).

Finally, make sure to stop the PostgreSQL services __everywhere__ and to
disable them, as Pacemaker will take care of starting/stopping everything for
you during cluster normal cluster operations. Start with the primary:

~~~bash
systemctl disable --now postgresql@12-main
echo disabled > /etc/postgresql/12/main/start.conf
~~~

And remove the vIP address from `srv1`:

~~~bash
ip addr del 192.168.122.70/24 dev eth0
~~~


## Cluster pre-requisites

This guide uses the cluster management tool `pcsd` to ease the creation and
setup of a cluster. It allows to create the cluster from command line, without
editing configuration files or XML by hands.

`pcsd` uses the `hacluster` system user to work and communicate with other
members of the cluster. We need to set a password to this user so it can
authenticate to other nodes easily. As cluster management commands can be run on
any member of the cluster, it is recommended to set the same password everywhere
to avoid confusions:

~~~bash
passwd hacluster
~~~

Make sure the `pcsd` daemon is enabled and started on all nodes:

~~~bash
systemctl enable --now pcsd
~~~

Now, authenticate each node to the other ones using the following command, on
each nodes. The command ask for the `hacluster` password:

~~~bash
pcs host auth -u hacluster srv1 srv2 srv3
~~~


## Cluster creation

The `pcs` cli tool is able to create and start the whole cluster for us. From
one of the nodes, run the following command:

~~~bash
pcs cluster setup cluster_pgsql srv1 srv2 srv3
~~~

> **NOTE**: Make sure you have a redundant network at system level. This is a
> __**CRITICAL**__ part of your cluster. If you have second interfaces not in
> bonding or teaming already (prefered method), you can add them to the cluster
> setup using eg.:
>
> ~~~
> pcs cluster setup cluster_pgsql srv1,srv1-alt srv2,srv2-alt srv3,srv3-alt
> ~~~
{: .notice}

This command creates the `/etc/corosync/corosync.conf` file and propagate
it everywhere. For more information about it, read the `corosync.conf(5)`
manual page.

> **WARNING**: whatever you edit in your `/etc/corosync/corosync.conf` file,
> __**ALWAYS**__ make sure all the nodes in your cluster has the exact same
> copy of the file. You can use `pcs cluster sync`.
{: .warning}


It is advised to keep Pacemaker off on server boot. It helps the administrator
to investigate after a node fencing before Pacemaker starts and potentially
enters in a death match with the other nodes. Make sure to disable Corosync as
well to avoid unexpected behaviors. Run this on all nodes:

~~~bash
pcs cluster disable --all
~~~

You can now start the whole cluster from one node:

~~~bash
pcs cluster start --all
~~~

After some seconds of startup and cluster membership stuffs, you should be able
to see your three nodes up in `crm_mon` (or `pcs status`):

~~~bash
root@srv1:~# crm_mon -n1D

Node srv1: online
Node srv2: online
Node srv3: online
~~~

Now the cluster run, let's start with some basic setup of the cluster. Run
the following command from **one** node only (the cluster takes care of
broadcasting the configuration on all nodes):

~~~bash
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

The most important resource in your cluster is the one able to fence a
node. Please, stop reading this quick start and read our fencing
documentation page before building your cluster. Take a deep breath, and read:
[http://clusterlabs.github.com/PAF/fencing.html]({{ site.baseurl }}/fencing.html).

> **WARNING**: I really mean it. You need fencing. PAF is expecting fencing to
> work in your cluster. Without fencing, you will experience cluster refusing
> to move anything, even with stonith disabled, or worst, a split brain if you
> bend it hard enough to make it work anyway.
> If you don't mind taking time rebuilding a database with corrupt and/or
> incoherent data and constraints, that's fine though.
{: .warning}

> **NOTE**: if you can't have active fencing, look as storage base death or
> watchdog methods. They are both described in the fencing documentation.
{: .notice}

In this tutorial, we choose to create one fencing resource per node to fence.
They are called `fence_vm_xxx`and use the fencing agent `fence_virsh`, allowing
to power on or off a virtual machine using the `virsh` command through a ssh
connection to the hypervisor.

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

~~~bash
ssh-keygen
ssh-copy-id <user>@192.168.122.1
~~~

Check the ssh connections are working as expected.

We can now create one STONITH resource for each node. Each fencing
resource will not be allowed to run on the node it is supposed to fence.
Note that in the `port` argument of the following commands, `d10_srv[1-3]` are
the names of the virutal machines as known by libvirtd side. See manpage 
fence_virsh(8) for more infos.

~~~bash
pcs cluster cib fencing.xml
pcs -f fencing.xml stonith create fence_vm_srv1 fence_virsh \
  pcmk_host_check="static-list" pcmk_host_list="srv1"        \
  ipaddr="192.168.122.1" login="<user>" port="d10_srv1"      \
  identity_file="/root/.ssh/id_rsa"

pcs -f fencing.xml stonith create fence_vm_srv2 fence_virsh \
  pcmk_host_check="static-list" pcmk_host_list="srv2"        \
  ipaddr="192.168.122.1" login="<user>" port="d10_srv2"      \
  identity_file="/root/.ssh/id_rsa"

pcs -f fencing.xml stonith create fence_vm_srv3 fence_virsh \
  pcmk_host_check="static-list" pcmk_host_list="srv3"        \
  ipaddr="192.168.122.1" login="<user>" port="d10_srv3"      \
  identity_file="/root/.ssh/id_rsa"

pcs -f fencing.xml constraint location fence_vm_srv1 avoids srv1=INFINITY
pcs -f fencing.xml constraint location fence_vm_srv2 avoids srv2=INFINITY
pcs -f fencing.xml constraint location fence_vm_srv3 avoids srv3=INFINITY
pcs cluster cib-push scope=configuration fencing.xml
~~~

Using `crm_mon` You should see the three resources appearing in your cluster
and being dispatched on nodes.


## Cluster resources

In this last chapter we create three resources: `pgsqld`, `pgsqld-clone`
and `pgsql-pri-ip`.

The `pgsqld` defines the properties of a PostgreSQL instance: where it is
located, where are its binaries, its configuration files, how to montor it, and
so on.

The `pgsqld-clone` resource controls all the PostgreSQL instances `pgsqld` in
your cluster, decides where the primary is promoted and where the standbys
are started.

The `pgsql-pri-ip` resource controls the `pgsql-vip` IP address. It is
started on the node hosting the PostgreSQL primary resource.

Now the fencing is working, we can add all other resources and constraints all
together in the same time. Create a new offline CIB:

~~~bash
pcs cluster cib cluster1.xml
~~~

We add the PostgreSQL `pgsqld` resource and the multistate `pgsqld-clone`
responsible to clone it everywhere and define the roles (`Master`/`Slave`) of
each clone:

~~~bash
# pgsqld
pcs -f cluster1.xml resource create pgsqld ocf:heartbeat:pgsqlms    \
    bindir="/usr/lib/postgresql/12/bin"                             \
    pgdata="/etc/postgresql/12/main"                                \
    datadir="/var/lib/postgresql/12/main"                           \
    op start timeout=60s                                            \
    op stop timeout=60s                                             \
    op promote timeout=30s                                          \
    op demote timeout=120s                                          \
    op monitor interval=15s timeout=10s role="Master"               \
    op monitor interval=16s timeout=10s role="Slave"                \
    op notify timeout=60s                                           \
    promotable notify=true
~~~

Note that the values for `timeout` and `interval` on each operation are based
on the minimum suggested value for PAF Resource Agent. These values should be
adapted depending on the context.

The last line of this command declare the resource `pgsqld` as promotable. This
is handled by `pcs` which creates the `pgsqld-clone` resource automatically.

We add the IP address which should be started on the primary node:

~~~bash
pcs -f cluster1.xml resource create pgsql-pri-ip ocf:heartbeat:IPaddr2 \
    ip=192.168.122.70 cidr_netmask=24 op monitor interval=10s
~~~

We now define the collocation between `pgsqld-clone` and `pgsql-pri-ip`. The
start/stop and promote/demote order for these resources must be asymetrical: we
__MUST__ keep the vIP on the primary during its demote process so the
standbies receive everything during the primary shutdown.

~~~bash
pcs -f cluster1.xml constraint colocation add pgsql-pri-ip with master pgsqld-clone INFINITY
pcs -f cluster1.xml constraint order promote pgsqld-clone then start pgsql-pri-ip symmetrical=false kind=Mandatory
pcs -f cluster1.xml constraint order demote pgsqld-clone then stop pgsql-pri-ip symmetrical=false kind=Mandatory
~~~

We can now push our CIB to the cluster, which will start all the magic stuff:

~~~bash
pcs cluster cib-push scope=configuration cluster1.xml
~~~


## Conclusion

Now you know the basics to build a Pacemaker cluster hosting some PostgreSQL
instances replicating with each others, you should probably check:

* [how to set up properly the PostgreSQL replication](https://www.postgresql.org/docs/current/static/high-availability.html)
* Documentation about how to setup network bonding or teaming are popular on
  internet.  You can consult the Corosync documentation to support redundancy
  from there, but it best fits in the operating system layer.
* have a look at our basic
  [administration cookbooks]({{ site.baseurl}}/documentation.html#administration).
  You mostly should look and adapt for Debian the one for [CentOS 7 using pcs]({{ site.baseurl}}/CentOS-7-admin-cookbook.html)

