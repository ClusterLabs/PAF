---
layout: default
title: PostgreSQL Automatic Failover - Quick start Debian 9 using crm
---

# Quick Start Debian 9 using crm

This quick start tutorial is based on Debian 9.1, using Pacemaker 1.1.16 and
the `crm` command version 2.3.2.

Table of contents:

* [Repository setup](#repository-setup)
* [Network setup](#network-setup)
* [PostgreSQL and Cluster stack installation](#postgresql-and-cluster-stack-installation)
* [PostgreSQL setup](#postgresql-setup)
* [Cluster pre-requisites](#cluster-pre-requisites)
* [Cluster creation](#cluster-creation)
* [Node fencing](#node-fencing)
* [Cluster resources](#cluster-resources)


## Repository setup

To install PostgreSQL, this tutorial uses the PGDG repository maintained by the
PostgreSQL community (and actually Debian maintainers). Here is how to add it:

~~~
cat <<EOF >> /etc/apt/sources.list.d/pgdg.list
deb http://apt.postgresql.org/pub/repos/apt/ stretch-pgdg main
EOF
~~~

Now, update your local apt cache:

~~~
apt install ca-certificates
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add
apt update
apt install pgdg-keyring
~~~


## Network setup

The cluster we are about to build includes three servers called `srv1`,
`srv2` and `srv3`. Each of them have two network interfaces `eth0` and
`eth1`. IP addresses of these servers are `192.168.122.6x/24` on the first
interface, `192.168.123.6x/24` on the second one.

The IP address `192.168.122.60`, called `pgsql-vip` in this tutorial, will be
set on the server hosting the master PostgreSQL instance.

During the cluster setup, we use the node names in various places,
make sure all your server hostnames can be resolved to the correct IPs. We
usually set this in the `/etc/hosts` file:

~~~
192.168.122.60 pgsql-vip
192.168.122.61 srv1
192.168.122.62 srv2
192.168.122.63 srv3
192.168.123.61 srv1-alt
192.168.123.62 srv2-alt
192.168.123.63 srv3-alt
~~~

Now, the three servers should be able to ping each others, eg.:

~~~
root@srv1:~# for s in srv1 srv2 srv3; do ping -W1 -c1 $s; done| grep icmp_seq
64 bytes from srv1 (192.168.122.61): icmp_seq=1 ttl=64 time=0.028 ms
64 bytes from srv2 (192.168.122.62): icmp_seq=1 ttl=64 time=0.296 ms
64 bytes from srv3 (192.168.122.63): icmp_seq=1 ttl=64 time=0.351 ms
~~~


## PostgreSQL and Cluster stack installation

Run this whole chapter on ALL nodes.

Let's install everything we need: PostgreSQL, Pacemaker and cluster related
packages:

~~~
apt install --no-install-recommends pacemaker fence-agents crmsh net-tools
apt install postgresql-9.6 postgresql-contrib-9.6 postgresql-client-9.6
~~~

We add the `--no-install-recommends` because the apt tools are setup by default
to install all recommended packages in addition to the usual dependences. This
might be fine in most case, but we want to keep this quick start small, easy
and clear. Installing recommended packages requires some more attention on
other subjects not related to this document (eg. setting up some IPMI daemon).

Next, we need to install the "PostgreSQL Automatic Failover" (PAF) resource
agent:

~~~
wget 'https://github.com/dalibo/PAF/releases/download/v2.2.0/resource-agents-paf_2.2.0-1_all.deb'
dpkg -i resource-agents-paf_2.2.0-1_all.deb
apt -f install
~~~

By default, Debian set up the instances to put the temporary activity
statistics inside a sub folder of `/var/run/postgresql/`. This sub folder is
created by the debian specific tool `pg_ctlcluster` on instance startup.

PAF only use tools provided by the PostgreSQL projects, not other specifics to
some other packages or operating system. That means that this required sub
folder set up in `stats_temp_directory` is never created and leads to error on
instance startup by Pacemaker.

To create this sub folder on system initialization, we need to extend the
existing `systemd-tmpfiles` configuration for `postgresql` to add it. In our
environment `stats_temp_directory` is set
to `/var/run/postgresql/9.6-main.pg_stat_tmp`, so we create the following
file:

~~~
cat <<EOF > /etc/tmpfiles.d/postgresql-part.conf
# Directory for PostgreSQL temp stat files
d /var/run/postgresql/9.6-main.pg_stat_tmp 0700 postgres postgres - -
EOF
~~~

To take this file in consideration immediately without rebooting the server,
run the following command:

~~~
systemd-tmpfiles --create /etc/tmpfiles.d/postgresql-part.conf
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

> **NOTE**: as `recovery.conf.pcmk` and `pg_hba.conf` files are different
> on each node, make sure to keep them out of the `$PGDATA` so you do not have
> to deal with them (or worst: forget to edit them) each time you rebuild a
> standby! Luckily, Debian packaging already enforce this as configuration files
> are all located in `/etc/postgresql`.
{: .notice}

Here are some quick steps to build your primary PostgreSQL instance and its
standbys. This quick start considers `srv1` is the preferred master.

On all nodes:

~~~
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
host replication postgres 192.168.122.60/32 reject
host replication postgres $(hostname -s) reject

# allow any standby connection
host replication postgres 0.0.0.0/0 trust
EOP

cat <<EOP > recovery.conf.pcmk
standby_mode = on
primary_conninfo = 'host=192.168.122.60 application_name=$(hostname -s)'
recovery_target_timeline = 'latest'
EOP

exit
~~~

On `srv1`, the master, restart the instance and give it the master IP address:

~~~
systemctl restart postgresql@9.6-main

ip addr add 192.168.122.60/24 dev eth0
~~~

Now, on each standby (`srv2` and `srv3` here), we have to cleanup the instance
created by the package and clone the primary. E.g.:

~~~
systemctl stop postgresql@9.6-main
su - postgres

rm -rf 9.6/main/
pg_basebackup -h pgsql-vip -D ~postgres/9.6/main/ -X stream -P

cp /etc/postgresql/9.6/main/recovery.conf.pcmk ~postgres/9.6/main/recovery.conf

exit

systemctl start postgresql@9.6-main
~~~

Finally, make sure to stop the PostgreSQL services __everywhere__ and to
disable them, as Pacemaker will take care of starting/stopping everything for
you. Start with your master:

~~~
systemctl stop postgresql@9.6-main
systemctl disable postgresql@9.6-main
echo disabled > /etc/postgresql/9.6/main/start.conf
~~~

And remove the master IP address from `srv1`:

~~~
ip addr del 192.168.122.60/24 dev eth0
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

Moreover, on Pacemaker and Corosync installation, Debian packaging
automatically creates and start a dummy isolated node. We need to move it out
of our way by stopping it before creating the real one:

~~~
systemctl stop pacemaker.service corosync.service
~~~


This guide uses the cluster management tool `crm` to ease the creation and
setup of a cluster. It allows to create the cluster from command line, without
editing configuration files or XML by hands.

`crm` relies heavily on SSH to transfer files between nodes and execute remote
commands. It requires the system user `root` to be able to connect to all
remote nodes without password. The easiest way to go is to generate a SSH keys
on each node and put the public part in the `~root/.ssh/authorized_keys` file
on other nodes.

On all nodes:

~~~
ssh-keygen # do no set any password
ssh-copy-id srv1
ssh-copy-id srv2
ssh-copy-id srv3
~~~


## Cluster creation

The `crm` cli tool is able to create and start the whole cluster for us. From
one of the nodes, run the following command:

~~~
crm cluster init srv1 srv2 srv3
~~~

This command creates the `/etc/corosync/corosync.conf` file and propagate
it everywhere. This file must **always** be the same among all nodes. For more
information about it, read the `corosync.conf(5)` manual page.

Your cluster is now supposed to run, the following command should prove it,
just give it some time for the node to negotiate between them:

~~~
crm status
~~~

If this command returns an error after some time, start the cluster yourself by
hand running the following command on all nodes:

~~~
crm cluster start
~~~

After some seconds of startup and cluster membership stuff, you should be able
to see your three nodes up in `crm_mon` (or `crm status`):

~~~
root@srv1:~# crm_mon -n1D
Node srv1: online
Node srv2: online
Node srv3: online
~~~


> **WARNING**: make sure you have a redundant network at system level. This is a
> __**CRITICAL**__ part of your cluster. `crm` does not support redundant rings
> configuration in corosync.
> To avoid having your network being a SPoF, either setup some redundancy on
> network link level (better) or edit by hands the corosync configuration to
> add a second ring (good enough) using the following commands:
>
> ~~~
> crm corosync edit
> crm corosync push
> ~~~
>
> Here is a sample diff-formated edition of `/etc/corosync/corosync.conf` to
> add the second ring:
>
> ~~~
> @@ -16,10 +16,12 @@
>  	interface {
>  		ringnumber: 0
>  		bindnetaddr: 192.168.122.0
> -		mcastaddr: 239.19.196.75
> -		mcastport: 5405
> -		ttl: 1
>  	}
> +	interface {
> +		ringnumber: 1
> +		bindnetaddr: 192.168.123.0
> +	}
> +	rrp_mode: passive
>  	transport: udpu
>  }
>  
> @@ -41,16 +43,19 @@
>  
>      node {
>          ring0_addr: srv1
> +        ring1_addr: srv1-alt
>          nodeid: 1
>      }
>  
>      node {
>          ring0_addr: srv3
> +        ring1_addr: srv3-alt
>          nodeid: 2
>      }
>  
>      node {
>          ring0_addr: srv2
> +        ring1_addr: srv2-alt
>          nodeid: 3
>      }
> 
> ~~~
>
> You will need to restart the cluster after such a change. Run on all node:
>
> ~~~
> crm cluster stop
> crm cluster start
> ~~~
{: .warning}

> **WARNING**: whatever you edit in your `/etc/corosync/corosync.conf` file,
> __**ALWAYS**__ make sure all the nodes in your cluster has the exact same
> copy of the file.
{: .warning}

Here is a command to check everything is working correctly (might differ if you
only have one ring):

~~~
root@srv1:~# corosync-cmapctl | grep 'members.*ip'
runtime.totem.pg.mrp.srp.members.1.ip (str) = r(0) ip(192.168.122.61) r(1) ip(192.168.123.61)
runtime.totem.pg.mrp.srp.members.2.ip (str) = r(0) ip(192.168.122.63) r(1) ip(192.168.123.63)
runtime.totem.pg.mrp.srp.members.3.ip (str) = r(0) ip(192.168.122.62) r(1) ip(192.168.123.62)
~~~

Now the cluster run, let's start with some basic setup of the cluster. Run
the following command from **one** node only (the cluster takes care of
broadcasting the configuration on all nodes):

~~~
crm conf <<EOC
rsc_defaults resource-stickiness=10
rsc_defaults migration-threshold=5
EOC
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
[http://dalibo.github.com/PAF/fencing.html]({{ site.baseurl }}/fencing.html).

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

> **NOTE**: if you don't mind spending some time in your
> `/etc/libvirt/libvirtd.conf` file on the hypervisor, you might want to use
> the fencing agent `external/libvirt` instead of `fence_virsh`. It avoids the
> SSH connection from VM to hypervisor, but requires some more setup.
{: .notice}

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
ssh-copy-id <user>@192.168.122.1
~~~

Check the ssh connections are working as expected.

We can now create one STONITH resource for each node. Each fencing
resource will not be allowed to run on the node it is supposed to fence.
Note that in the `port` argument of the following commands, `srv[1-3]-d9` are 
the names of the virutal machines as known by libvirtd side. See manpage 
fence_virsh(8) for more infos.

~~~
crm conf<<EOC
primitive fence_vm_srv1 stonith:fence_virsh                   \
  params pcmk_host_check="static-list" pcmk_host_list="srv1"  \
         ipaddr="192.168.122.1" login="<user>"                \
         identity_file="/root/.ssh/id_rsa"                    \
         port="srv1-d9" action="off"                          \
  op monitor interval=10s

primitive fence_vm_srv2 stonith:fence_virsh                   \
  params pcmk_host_check="static-list" pcmk_host_list="srv2"  \
         ipaddr="192.168.122.1" login="<user>"                \
         identity_file="/root/.ssh/id_rsa"                    \
         port="srv2-d9" action="off"                          \
  op monitor interval=10s

primitive fence_vm_srv3 stonith:fence_virsh                   \
  params pcmk_host_check="static-list" pcmk_host_list="srv3"  \
         ipaddr="192.168.122.1" login="<user>"                \
         identity_file="/root/.ssh/id_rsa"                    \
         port="srv3-d9" action="off"                          \
  op monitor interval=10s

location fence_vm_srv1-avoids-srv1 fence_vm_srv1 -inf: srv1
location fence_vm_srv2-avoids-srv2 fence_vm_srv2 -inf: srv2
location fence_vm_srv3-avoids-srv3 fence_vm_srv3 -inf: srv3
EOC
~~~

Using `crm_mon` You should see the three resources appearing in your cluster
and being dispatched on nodes.


## Cluster resources

In this last chapter we create three resources: `pgsqld`, `pgsql-ha`
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
together in the same time:

  1. the PostgreSQL `pgsqld` resource
  2. the multistate `pgsql-ha` responsible to clone `pgsqld` everywhere and
     define the roles (master/slave) of each clone
  3. the IP address that must be started on the PostgreSQL master node
  4. the collocation of the master IP address with the PostgreSQL master
     instance
  5. the ordering constraints between the IP address and the PostgreSQL master

~~~
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
  params ip=192.168.122.60 cidr_netmask=24 \
  op monitor interval=10s

# 4. colocation of the pgsql-ha master and the master IP address
colocation ip-with-master inf: pgsql-master-ip pgsql-ha:Master

# 5. ordering constraint
order promote-then-ip Mandatory:         \
  pgsql-ha:promote pgsql-master-ip:start \
  sequential=true symmetrical=false

order demote-then-stop-ip Mandatory:   \
  pgsql-ha:demote pgsql-master-ip:stop \
  sequential=true symmetrical=false

EOC
~~~

In step 5, the start/stop and promote/demote order for these
resources must be asymetrical: we __MUST__ keep the master IP on the master
during its demote process so the standbies receive everything during the
master shutdown.

Note that the values for `timeout` and `interval` on each operation are based
on the minimum suggested value for PAF Resource Agent. These values should be
adapted depending on the context.

