---
layout: default
title: PostgreSQL Automatic Failover - Quick start CentOS 7
---
# Quick Start

This quick start tutorial is based on CentOS 6.6, using the `pcs` command.


## Network setup

First, we should make sure NetworkManager is disabled. The network setup should
NOT be dynamically handled by some external daemons. Only Pacemaker related
processes should be able to deal with this:

```
chkconfig NetworkManager off
service NetworkManager stop
```

During the cluster setup, we use the cluster name in various places, make sure
all your servers names can be resolved to the correct IPs. We usually set this
in the `/etc/hosts` file:

```
192.168.1.51 srv1
192.168.1.52 srv2
192.168.1.53 srv3
192.168.2.51 srv1-adm
192.168.2.52 srv2-adm
192.168.2.53 srv3-adm
```

Finally, we have to allow the network traffic related to the cluster and
PostgreSQL to go through the firewalls:

```
service iptables start

# corosync
iptables -I INPUT -p udp -m state --state NEW -m multiport --dports 5404,5405 -j ACCEPT

# pcsd
iptables -I INPUT -p tcp --dport 2224 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -I OUTPUT -p tcp --sport 2224 -m state --state ESTABLISHED -j ACCEPT

# postgres
iptables -I INPUT -p tcp --dport 5432 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -I OUTPUT -p tcp --sport 5432 -m state --state ESTABLISHED -j ACCEPT

service iptables save
```

## PostgreSQL and Cluster stack installation

We are using the PostgreSQL packages from the PGDG repository. Here is how to
install and set up this repository on your system:

```
yum install http://yum.postgresql.org/9.3/redhat/rhel-6-x86_64/pgdg-centos93-9.3-1.noarch.rpm
```

Make sure to double adapt the previous command with the latest package available
and the PostgreSQL version you need.

We can now install everything we need for our cluster:

```
yum install -y corosync pacemaker postgresql93 postgresql93-contrib postgresql93-server resource-agents pcs pcsd cman perl-Module-Build
```

Finally, we download and install the `pgsql-resource-agent` resource agent:

```
cd /usr/local/src
git clone https://github.com/dalibo/PAF.git
cd pgsql-resource-agent/multistate
perl Build.PL
./Build
sudo ./Build install
```

## PostgreSQL setup

The resource agent requires the PostgreSQL instances to be already set up and
ready to start. Moreover, it requires a `recovery.conf` template ready to use.
You can create a `recovery.conf` file suitable to your needs, the only
requirements are:

  * have ``standby_mode = on``
  * have ``recovery_target_timeline = 'latest'``
  * a ``primary_conninfo`` with an ``application_name`` set to the node name

Here are some quick steps to build your primary postgres instance and its
standby. As this is not the main subject here, they are **quick and dirty**.
Rely on the PostgreSQL documentation for a proper setup.

On the primary:

```
# As root
service postgresql-9.3 initdb

# As postgres

cd 9.3/data/
cat <<EOP >> postgresql.conf

listen_addresses = '*'
wal_level = hot_standby
max_wal_senders = 10
hot_standby = on
hot_standby_feedback = on
EOP

cat <<EOP >> pg_hba.conf
host replication postgres 0.0.0.0/0 trust
EOP

cat <<EOP > recovery.conf.pcmk
standby_mode = on
primary_conninfo = 'host=192.168.1.50'
recovery_target_timeline = 'latest'
EOP

# As root

service postgresql-9.3 start
```

Now, on each standby, clone the primary. E.g.:

```
pg_basebackup -h srv1 -D ~postgres/9.3/data/ -X stream -R -P
```

Finally, make sure to stop the PostgreSQL services __everywhere__ and to
disabling them, as Pacemaker will take care of starting/stopping everything for
you:

```
service postgresql-9.3 stop
chkconfig postgresql-9.3 off
```

## Cluster setup

This guide use the cluster management pcsd provided by RHEL to ease the creation
and setup of a cluster. It allows to create the cluster from command line,
without editing configuration files or XML by hands.

`pcsd` use the hacluster system user to work and communicate with other
members of the cluster. We need to set a password to this user so it can
authenticate to other nodes easily. As cluster management commands can be run on
any member of the cluster, it is recommended to set the same password everywhere
to avoid confusions :

```
passwd hacluster
```

Enable and start the pcsd daemon on all the nodes:

```
chkconfig pcsd on
service pcsd start
```

Now, authenticate each node to the other ones using the following command:

```
pcs cluster auth srv1 srv2 srv3 -u hacluster
```

We can now create our cluster!

```
pcs cluster setup --name cluster_pgsql srv1 srv2 srv3
```

If you have alternative network available (this is highly recommended), you can
use the following syntax:

```
pcs cluster setup --name cluster_pgsql srv1,srv1-adm srv2,srv2-adm srv3,srv3-adm
```

If your version of `pcs` does not support it, you can fallback on the old but
useful `ccs`:

```
pcs cluster setup --name cluster_pgsql srv1 srv2 srv3
ccs -f /etc/cluster/cluster.conf --addalt srv1 srv1-adm
ccs -f /etc/cluster/cluster.conf --addalt srv2 srv2-adm
ccs -f /etc/cluster/cluster.conf --addalt srv3 srv3-adm
pcs cluster sync
```

You can now start your cluster!

```
pcs cluster start --all
```


## Cluster resource creation and management

This setup create three different resources: `pgsql-ha`, `pgsql-master-ip`
and `fence_ifmib_xxx`.

The `pgsql-ha` resource represent all the PostgreSQL instances of your cluster
and control where is the primary and who are the standbys. The
`pgsql-master-ip` is located on the node hosting the postgres master. The last
resources `fence_ifmib_xxx` are stonith resource: we create one stonith
resource for each node. Each fencing resource will not be allowed to run on the
node it is suppose to stop. We are using the fence_ifmib stonith agent, which is
an I/O fencing agent allowing to control network switch through the SNMP
protocol. For more information about fencing, see documentation
multistate/docs/FENCING.md.

First of all, let's create an empty CIB file and fill it with some basic setup.
We will push to the cluster once we are completely done:

```
pcs cluster cib cluster1.xml
pcs -f cluster1.xml property set no-quorum-policy=ignore
pcs -f cluster1.xml resource defaults migration-threshold=5
pcs -f cluster1.xml resource defaults resource-stickiness=INFINITY
```

Then, we must start populating it with the stonith resources:

```
pcs -f cluster1.xml stonith create fence_ifmib_srv1 fence_ifmib pcmk_host_check="static-list" pcmk_host_list="srv1" ipaddr="192.168.1.4" port="11" community="private" action="off"
pcs -f cluster1.xml stonith create fence_ifmib_srv2 fence_ifmib pcmk_host_check="static-list" pcmk_host_list="srv2" ipaddr="192.168.1.4" port="12" community="private" action="off"
pcs -f cluster1.xml stonith create fence_ifmib_srv3 fence_ifmib pcmk_host_check="static-list" pcmk_host_list="srv3" ipaddr="192.168.1.4" port="13" community="private" action="off"
pcs -f cluster1.xml constraint location fence_ifmib_srv1 avoids srv1=INFINITY
pcs -f cluster1.xml constraint location fence_ifmib_srv2 avoids srv2=INFINITY
pcs -f cluster1.xml constraint location fence_ifmib_srv3 avoids srv3=INFINITY
```

We add the PostgreSQL `pgsqld` resource and the multistate `pgsql-ha`
responsible to clone it everywhere and define the roles (master/slave) of each
clone:

```
# pgsqld
pcs -f cluster1.xml resource create pgsqld ocf:heartbeat:pgsqlms \
    bindir=/usr/pgsql-9.3/bin pgdata=/var/lib/pgsql/9.3/data     \
    op monitor interval=9s role="Master"                         \
    op monitor interval=10s role="Slave"

# pgsql-ha
pcs -f cluster1.xml resource master pgsql-ha pgsqld \
    master-max=1 master-node-max=1                  \
    clone-max=3 clone-node-max=1 notify=true
```

We add the IP addresse which should be started on the primary node:

```
pcs -f cluster1.xml resource create pgsql-master-ip ocf:heartbeat:IPaddr2 \
    ip=192.168.1.50 cidr_netmask=24 op monitor interval=10s
```

We now define the collocation between `pgsql-ha` and `pgsql-master-ip`.
Note that the start/stop and promote/demote order for these resource is
asymetrical: we __must__ keep the master IP on the master during its demote
process.

```
pcs -f cluster1.xml constraint colocation add pgsql-master-ip with master pgsql-ha INFINITY
pcs -f cluster1.xml constraint order promote pgsql-ha then start pgsql-master-ip symmetrical=false
pcs -f cluster1.xml constraint order demote pgsql-ha then stop pgsql-master-ip symmetrical=false
```

And finally, we define a preference for our master node:

```
pcs -f cluster1.xml constraint location pgsql-ha prefers srv1=1
```

We can now push our CIB to the cluster, which will start all the magic stuff:

```
pcs cluster cib-push cluster1.xml
```

## Adding a node to the cluster

Setup your new node following the first chapters. Stop after the PostgreSQL
setup.

On this new node, setup the pcsd deamon and its authentication:

```
passwd hacluster
chkconfig pcsd on
service pcsd start
pcs cluster auth srv1 srv2 srv3 srv4 -u hacluster
```

On all other node, authenticate to the new node:

```
pcs cluster auth srv4 -u hacluster
```

We are now ready to add the new node. Put the cluster in maintenance mode so it
does not move resources all over the place when the new node appears:

```
pcs property set maintenance-mode=true
pcs cluster node add srv4,srv41
```

Or, using the old commands if the syntax of `pcs` with alternate interface is
not supported:

```
pcs cluster node add srv4
ccs -f /etc/cluster/cluster.conf --addalt srv4 srv4-adm
pcs cluster sync
```

And reload the corosync configuration on all the nodes if needed (it just fail
if not needed):

```
pcs cluster reload corosync
```

We now need to allow more clone in the cluster:

```
pcs resource meta pgsql-ha clone-max=4
```

Add the stonith agent for the new node:

```
pcs stonith create fence_ifmib_srv4 fence_ifmib pcmk_host_check="static-list" pcmk_host_list="srv4" ipaddr="192.168.1.4" port="14" community="private" action="off"
pcs constraint location fence_ifmib_srv4 avoids srv4=INFINITY
```

And you can now exit your maintenance mode:

```
pcs property set maintenance-mode=false
```
