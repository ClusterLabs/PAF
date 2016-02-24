---
layout: default
title: PostgreSQL Automatic Failover - Quick start CentOS 7
---

# Quick Start CentOS 7

This quick start tutorial is based on CentOS 7.2, using the `pcs` command.


## Network setup

The cluster we are about to build include three servers called `srv1`,
`srv2` and `srv3`. Each of them have two network interfaces `ens3` and
`ens8`. IP addresses of these servers are `192.168.122.5x/24` on the first
interface, `192.168.123.5x/24` on the second one.

Considering the firewall, we have to allow the network traffic related to the
cluster and PostgreSQL to go through the firewalls:

```
firewall-cmd --permanent --add-service=high-availability
firewall-cmd --add-service=high-availability
firewall-cmd --permanent --add-service=postgresql
firewall-cmd --add-service=postgresql
```


During the cluster setup, we use the cluster name in various places,
make sure all your servers names can be resolved to the correct IPs. We usually
set this in the `/etc/hosts` file:

```
192.168.122.51 srv1
192.168.122.52 srv2
192.168.122.53 srv3
192.168.123.51 srv1-alt
192.168.123.52 srv2-alt
192.168.123.53 srv3-alt
```

Now, the three servers should be able to ping each others, eg.:

```
root@srv1:~# for s in srv1 srv2 srv3; do ping -W1 -c1 $s; done| grep icmp_seq
64 bytes from srv1 (192.168.122.51): icmp_seq=1 ttl=64 time=0.028 ms
64 bytes from srv2 (192.168.122.52): icmp_seq=1 ttl=64 time=0.296 ms
64 bytes from srv3 (192.168.122.53): icmp_seq=1 ttl=64 time=0.351 ms
```

##PostgreSQL and Cluster stack installation

We are using the PostgreSQL packages from the PGDG repository. Here is how to
install and set up this repository on your system:

```
yum install -y http://yum.postgresql.org/9.3/redhat/rhel-7-x86_64/pgdg-centos93-9.3-1.noarch.rpm
```

Make sure to double adapt the previous command with the latest package available
and the PostgreSQL version you need.

We can now install everything we need for our cluster:

```
yum install -y pacemaker postgresql93 postgresql93-contrib postgresql93-server resource-agents pcs perl-Module-Build fence-agents-all fence-agents-virsh git
```

Finally, we download and install the `pgsql-resource-agent` resource agent:

```
cd /usr/local/src
git clone https://github.com/dalibo/PAF.git
cd PAF
perl Build.PL
./Build
sudo ./Build install
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
standby. As this is not the main subject here, they are __**quick and dirty**__.
Rely on the PostgreSQL documentation for a proper setup.

On the primary:

```
# As root

/usr/pgsql-9.3/bin/postgresql93-setup initdb

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
primary_conninfo = 'host=192.168.122.50 application_name=$(hostname -s)'
recovery_target_timeline = 'latest'
EOP

# As root

systemctl start postgresql-9.3
```

Now, on each standby, clone the primary. E.g.:

```
# As postgres
pg_basebackup -h srv1 -D ~postgres/9.3/data/ -X stream -P

cd ~postgres/9.3/data/

cat <<EOP > recovery.conf.pcmk
standby_mode = on
primary_conninfo = 'host=192.168.122.50 application_name=$(hostname -s)'
recovery_target_timeline = 'latest'
EOP
```

Finally, make sure to stop the PostgreSQL services __everywhere__ and to
disabling them, as Pacemaker will take care of starting/stopping everything for
you:

```
systemctl stop postgresql-9.3
systemctl disable postgresql-9.3
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
systemctl enable pcsd
systemctl start pcsd
```

Now, authenticate each node to the other ones using the following command:

```
pcs cluster auth srv1 srv2 srv3 -u hacluster
```

We can now create our cluster!

```
pcs cluster setup --name cluster_pgsql srv1,srv1-alt srv2,srv2-alt srv3,srv3-alt
```

If you don't have an alternative network available (this is really not
recommended), you can use the following syntax:

```
pcs cluster setup --name cluster_pgsql srv1 srv2 srv3
```

You can now start your cluster!
```
pcs cluster start --all
```


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
pcs -f cluster1.xml stonith create fence_vm_srv1 fence_virsh pcmk_host_check="static-list" pcmk_host_list="srv1" ipaddr="192.168.122.1" login="root" port="srv1-centos7" action="off" identity_file="/root/.ssh/id_rsa"
pcs -f cluster1.xml stonith create fence_vm_srv2 fence_virsh pcmk_host_check="static-list" pcmk_host_list="srv2" ipaddr="192.168.122.1" login="root" port="srv2-centos7" action="off" identity_file="/root/.ssh/id_rsa"
pcs -f cluster1.xml stonith create fence_vm_srv3 fence_virsh pcmk_host_check="static-list" pcmk_host_list="srv3" ipaddr="192.168.122.1" login="root" port="srv3-centos7" action="off" identity_file="/root/.ssh/id_rsa"
pcs -f cluster1.xml constraint location fence_vm_srv1 avoids srv1=INFINITY
pcs -f cluster1.xml constraint location fence_vm_srv2 avoids srv2=INFINITY
pcs -f cluster1.xml constraint location fence_vm_srv3 avoids srv3=INFINITY
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
    ip=192.168.122.50 cidr_netmask=24 op monitor interval=10s
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

