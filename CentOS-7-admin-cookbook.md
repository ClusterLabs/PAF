---
layout: default
title: PostgreSQL Automatic Failover - Cluster administration under CentOS 7
---

# Cluster administration under CentOS 7

In this document, we are working with cluster under CentOS 7.2 using mostly
the `pcs` command. It supposes that the `pcsd` deamon is enabled and running and
authentication between node is set up (see quick start).

Topics:

* [Starting or stopping the cluster](#starting-or-stopping-the-cluster)
* [Swapping master and slave roles between nodes](#swapping-master-and-slave-roles-between-nodes)
* [PAF update](#paf-update)
* [PostgreSQL minor upgrade](#postgresql-minor-upgrade)
* [Adding a node](#adding-a-node)
* [Removing a node](#removing-a-node)
* [Setting up a watchdog](#setting-up-a-watchdog)
* [Forbidding a PAF resource on a node](#forbidding-a-paf-resource-on-a-node)
* [Adding IPs on slaves nodes](#adding-ips-on-slaves-nodes)


## Starting or stopping the cluster

Here is the command to start the cluster on all existing nodes:

```
# pcs cluster start --all
srv2: Starting Cluster...
srv1: Starting Cluster...
srv3: Starting Cluster...
```

Here is the command to stop the cluster on the local node it is executed:

```
# pcs cluster stop
```

You can also add a designated node if needed, eg.:

```
# pcs cluster stop srv2
```

It stops or move away all the resources on the node, then stops Pacemaker and
Corosync.

Note that the cluster forbid you to stop too many nodes so it can keep the
quorum:

```
# pcs cluster stop
Error: Stopping the node will cause a loss of the quorum, use --force to override
```

We just replace `stop` with `start` for the opposite command, to start the
cluster on one node. These two commands are equivalent:

```
srv2# pcs cluster start # executed on srv2
srv1# pcs cluster start srv2 # executed from srv1
```

If you want to stop the cluster on all nodes, just add `--all` to your command:

```
# pcs cluster stop --all
srv3: Stopping Cluster (pacemaker)...
srv2: Stopping Cluster (pacemaker)...
srv1: Stopping Cluster (pacemaker)...
srv3: Stopping Cluster (corosync)...
srv2: Stopping Cluster (corosync)...
srv1: Stopping Cluster (corosync)...
```

This last command is perfectly safe and your cluster will start cleanly when
desired.


## Swapping master and slave roles between nodes

In this chapter, we describe how to move the master role from one node to the
other and getting back to the cluster the former master as a slave.

Here is the command to move the master role from `srv1` to `srv2`:

```
# pcs resource move --master pgsql-ha srv2
# pcs resource clear pgsql-ha
```

That's it. Note that the former master became a slave and start replicating with
the new master.

You could add `--wait` so the command exits when everything is done. Here is an
example moving back the master to `srv1`:

```
# pcs resource move --wait --master pgsql-ha srv1
Resource 'pgsql-ha' is master on node srv1; slave on node srv2.
# pcs resource clear pgsql-ha
```

To move the resource, `pcs` sets an `INFINITY` constraint location for the
master on the given node. You must clear this constraint to avoid unexpected
location behavior using the `pcs resource clear` command.

Note that giving the destination node is not mandatory. If no destination node
is given, `pcs` set a `-INFINITY` score for the master resource on its current
node to force it to move away:

```
# pcs resource move --wait --master pgsql-ha
Warning: Creating location constraint cli-ban-pgsql-ha-on-srv1 with a score of -INFINITY for resource pgsql-ha on node srv1.
This will prevent pgsql-ha from being promoted on srv1 until the constraint is removed. This will be the case even if srv1 is the last node in the cluster.
Resource 'pgsql-ha' is master on node srv2; slave on node srv1.

# pcs constraint show | grep Master
    Disabled on: srv1 (score:-INFINITY) (role: Master)

# pcs resource clear pgsql-ha

# pcs constraint show | grep Master
(nothing)
```

## PAF update

Updating the PostgreSQL Auto-Failover resource agent does not requires to stop
your PostgreSQL cluster. You just need to make sure the cluster manager do not
decide to run an action while the system updates the `pgsqlms` script or the
libraries. It's quite improbable, but this situation is still possible.

### Easiest and faster way to update PAF

The easiest way to acheive a clean update is to put the whole cluster in
maintenance mode and update PAF, eg.:

```
# pcs property set maintenance-mode=true
# yum install -y https://github.com/ClusterLabs/PAF/releases/download/v2.2.1/resource-agents-paf-2.2.1-1.noarch.rpm
# pcs property set maintenance-mode=false
```

That's it, you are done.

### Keep cluster's hands off PostgreSQL resources while updating PAF

If putting the whole cluster is not an option to you, you must ask the
cluster to only ignore and avoid your PostgreSQL resources. The cluster
will still be in charge of other resources.

Considers the PostgreSQL multistate resource is called `pgsql-ha`.

The following command achieve two goals. The first one forbids the cluster resource manager to react on unexpected
status by putting the resource in unmanaged mode (`unmanage pgsql-ha`). The second one stops the monitor actions for
this resources (`--monitor`).

```
# pcs resource unmanage pgsql-ha --monitor
```

Notice `(unmanaged)` appeared in `crm_mon`. In the following command, the meta attribute `is-managed=false` appeared
for the `pgsql-ha` resource and `enabled=false` appeared for the monitor actions:

```
# pcs resource show pgsql-ha
 Master: pgsql-ha
  Meta Attrs: notify=true
  Resource: pgsqld (class=ocf provider=heartbeat type=pgsqlms)
   Attributes: bindir=/usr/pgsql-10/bin pgdata=/var/lib/pgsql/10/data
   Meta Attrs: is-managed=false
   Operations: demote interval=0s timeout=120s (pgsqld-demote-interval-0s)
               methods interval=0s timeout=5 (pgsqld-methods-interval-0s)
               monitor enabled=false interval=15s role=Master timeout=10s (pgsqld-monitor-interval-15s)
               monitor enabled=false interval=16s role=Slave timeout=10s (pgsqld-monitor-interval-16s)
               notify interval=0s timeout=60s (pgsqld-notify-interval-0s)
               promote interval=0s timeout=30s (pgsqld-promote-interval-0s)
               reload interval=0s timeout=20 (pgsqld-reload-interval-0s)
               start interval=0s timeout=60s (pgsqld-start-interval-0s)
               stop interval=0s timeout=60s (pgsqld-stop-interval-0s)

```

Now, update PAF, eg.:

```
# yum install -y https://github.com/ClusterLabs/PAF/releases/download/v2.2.1/resource-agents-paf-2.2.1-1.noarch.rpm
```

We can now put the resource in `managed` mode again and enable the monitor actions:

```
# pcs resource manage pgsql-ha --monitor
```

> __NOTE__: you might want to enable monitor action first to check everything is going fine before getting back the
> control to the cluster. You can enable the monitor actions using the following commands (you __must__ to set all
> parameters related to the action):
>
> ```
> # pcs resource update pgsqld op monitor role=Master timeout=10s interval=15s enabled=true
> # pcs resource update pgsqld op monitor role=Slave timeout=10s interval=16s enabled=true
> ```
>
> Monitor action should be executed immediately and report no errors. Check that everything is running correctly in
> `crm_mon` and your log files before enabling the resource itself (without the `--monitor`):
> 
> ```
> # pcs resource manage pgsql-ha
> ```
{: .notice}


## PostgreSQL minor upgrade

This chapter explains how to do a minor upgrade of PostgreSQL on a two node
cluster. Nodes are called `srv1` and `srv2`, the PostgreSQL HA resource is
called `pgsql-ha`. Node `srv1` is hosting the master.

The process is quite simple: upgrade the standby first, move the master
role and finally upgrade PostgreSQL on the former PostgreSQL master node.

Here is how to upgrade PostgeSQL on the standby side:

```
# yum install --downloadonly postgresql93 postgresql93-contrib postgresql93-server
# pcs resource ban --wait pgsql-ha srv2
# yum install -y postgresql93 postgresql93-contrib postgresql93-server
# pcs resource clear pgsql-ha
```

Here are the details of these commands:

- download all the required packages
- ban the `pgsql-ha` resource __only__ from `srv2`, effectively stopping it
- upgrade the PostgreSQL packages
- allow the `pgsql-ha` resource to run on `srv2`, effectively starting it

Now, we can move the PostgreSQL master resource to `srv2`, then take care
of `srv1`:

```
# pcs resource move --wait --master pgsql-ha srv2
# yum install --downloadonly postgresql93 postgresql93-contrib postgresql93-server
# pcs resource ban --wait pgsql-ha srv1
# yum install -y postgresql93 postgresql93-contrib postgresql93-server
# pcs resource clear pgsql-ha
```

Minor upgrade is finished. Feel free to move your master back to `srv1` if you
really need it.


## Adding a node

In this chapter, we add server `srv3` hosting a PostgreSQL standby instance as a
new node in an existing two node cluster.

Setup everything so PostgreSQL can start on `srv3` as a slave and enter in
streaming replication. Remember to create the recovery configuration template
file, setup the `pg_hba.conf` file etc.

On this new node, setup the pcsd deamon and its authentication:

```
# passwd hacluster
# systemctl enable pcsd
# systemctl start pcsd
# pcs cluster auth srv1 srv2 srv3 -u hacluster
```

On all other nodes, authenticate to the new node:

```
# pcs cluster auth srv3 -u hacluster
```

We are now ready to add the new node.

> __NOTE__: Put the cluster in maintenance mode or use crm_simulate if you are
> afraid that some of your resources move all over the place when the new node
> appears
{: .notice}

```
# pcs cluster node add srv3
```

> __NOTE__: If corosync is set up to use multiple network for redundancy, use
> the following command:
>
> ```
> # pcs cluster node add srv3,srv3-alt
> ```
{: .notice}

Reload the corosync configuration on all the nodes if needed (it shouldn't, but
it doesn't hurt anyway):

```
# pcs cluster reload corosync
```

Fencing is mandatory. See: [http://clusterlabs.github.com/PAF/fencing.html]({{ site.baseurl }}/fencing.html).
Either edit the existing fencing resources to handle the new node if applicable,
or add a new one being able to do it. In the example, we are using
the `fence_virsh` fencing agent to create a dedicated fencing resource able to
only fence `srv3`:

```
# pcs stonith create fence_vm_srv3 fence_virsh pcmk_host_check="static-list" \
    pcmk_host_list="srv3" ipaddr="192.168.122.1"                             \
    login="<username>" port="srv3-c7" identity_file="/root/.ssh/id_rsa"      \
    action="off"
# pcs constraint location fence_vm_srv3 avoids srv3=INFINITY
```

We can now start the cluster on `srv3`:

```
# pcs cluster start
```

After some time checking cluster using `crm_mon` or `pcs status`, you should
find of `srv3` appearing in the cluster.

If your PosgreSQL standby is not started on the new node, maybe the cluster has
been setup with a hard `clone-max` value. Check with:

```
# pcs resource show pgsql-ha
```

If you get a value either:
* remove it if you don't mind having a clone on each node:
  
  ~~~
  # pcs resource meta pgsql-ha clone-max=
  ~~~
* set it to the needed value:
  
  ~~~
  # pcs resource meta pgsql-ha clone-max=3
  ~~~

Your standby instance should start shortly.


## Removing a node

This chapter explains how to remove a node called `srv3` from a three node
cluster.

The first command will put the node in standby. It stops __all__ resources on
the node:

```
# pcs cluster standby srv3
```

Next command simply remove the node from the cluster. It stops Pacemaker
on `srv3̀`, remove the cluster setup from it and reconfigure other nodes:

```
# pcs cluster node remove srv3
srv3: Stopping Cluster (pacemaker)...
srv3: Successfully destroyed cluster
srv1: Corosync updated
srv2: Corosync updated
```

If you choose to set a specific `clone-max` attribute to the `pgsql-ha`
resource, update it. You **don't** need to update it if it is not set (see
previous chapter).

```
# pcs resource meta pgsql-ha clone-max=2
```


## Setting up a watchdog

First, read [the watchdog chapter]({{ site.baseurl }}/fencing.html#using-a-watchdog-device)
of the "How to fence your node" documentation page for some theory.

We now explain how to setup a watchdog device as a fencing method in
Pacemaker. The `i6300esb` watchdog "hardware" has been added to the virtual
machines in our demo cluster. This hardware is correctly discovered on boot by
the kernel:

~~~
Dec  7 14:47:21 srv1 kernel: i6300esb: Intel 6300ESB WatchDog Timer Driver v0.05
Dec  7 14:47:21 srv1 kernel: i6300esb: initialized (0xffffc90000128000). heartbeat=30 sec (nowayout=0)
~~~

> **NOTE**: in your test environment, you could use a software watchdog from the
> Linux kernel called `softdog`. This is fine as far as this is just for demo
> purpose or very last possible solution. You should definitely rely on a
> hardware watchdog which is not tied to the operating system.
{: .notice}

First we need to stop the cluster to set everything up. The watchdog capability
is detected by the cluster manager on each node during the cluster startup.

~~~
# pcs cluster stop --all
~~~

Install and enable `sbd`. This small deamon is the glue between the watchdog
device and the inter-communication with Pacemaker:

~~~
# yum install -y sbd
# systemctl enable sbd.service
~~~

Edit `/etc/sysconfig/sbd` and make sure you
have `SBD_PACEMAKER=yes`, `SBD_WATCHDOG_DEV` pointing to the correct device
and adjust the value of `SBD_WATCHDOG_TIMEOUT` to suit your need. This last
variable is the time sbd will use to initialize the recurrent hardware watchdog
timer.

Start the cluster:

~~~
# pcs cluster start --all
~~~

After some seconds, the following command should return true:

~~~
# pcs property show | grep have-watchdog
 have-watchdog: true
~~~

Adjust the `stonith-watchdog-timeout` cluster property:

~~~~
# pcs property set stonith-watchdog-timeout=10s
~~~~

A good value for `stonith-watchdog-timeout` is the double
of `SBD_WATCHDOG_TIMEOUT`.

Now, if you kill the sbd process, the node should reset itself in less
than `SBD_WATCHDOG_TIMEOUT` seconds:

~~~
# killall -9 sbd
~~~

Using the following command should ask the remote node to fence itself using
its watchdog (if no other fencing device exist):

~~~
# stonith_admin -F srv1
~~~

If you stop Pacemaker but not Corosync or simulate a resource failing to
stop or a resource fatal error, the node should fence itself immediately.


## Forbidding a PAF resource on a node

In this chapter, we need to set up a node where no PostgreSQL instance of your
cluster is supposed to run. That might be that PostgreSQL is not installed on
this node, the instance is part of a different resource cluster, etc.

The following command forbid your multi-state PostgreSQL resource
called `pgsql-ha` to run on node called `srv3`:

```
# pcs constraint location pgsql-ha rule resource-discovery=never score=-INFINITY \#uname eq srv3
```

This creates constraint location associated to a rule allowing us to
avoid ( `score=-INFINITY` ) the node `srv3` ( `\#uname eq srv3` ) for
resource `pgsql-ha`. The `resource-discovery=never` is mandatory here as it
forbid the "probe" action the CRM is usually running to discovers the state of
a resource on a node. On a node where your PostgreSQL cluster is not running,
this "probe" action will fail, leading to bad cluster reactions.


## Adding IPs on slaves nodes

In this chapter, we are using a three node cluster with one PostgreSQL master
instance and two standbys instances.

As usual, we start from the cluster created in the quick start documentation:
* one master resource called `pgsql-ha`
* an IP address called `pgsql-master-ip` linked to the `pgsql-ha` master role

See the [Quick Start CentOS 7]({{ site.baseurl}}/Quick_Start-CentOS-7.html#cluster-resources)
for more informations.

We want to create two IP addresses with the following properties:
* start on a standby node
* avoid to start on the same standby node than the other one
* move to the available standby node should a failure occurs to the other one
* move to the master if there is no standby alive

To make this possible, we have to play with the resources co-location scores.

First, let's add two `IPaddr2` resources called `pgsql-ip-stby1` and
`pgsql-ip-stby2` holding IP addresses `192.168.122.49` and `192.168.122.48`:

~~~
# pcs resource create pgsql-ip-stby1 ocf:heartbeat:IPaddr2  \
  cidr_netmask=24 ip=192.168.122.49 op monitor interval=10s \

# pcs resource create pgsql-ip-stby2 ocf:heartbeat:IPaddr2  \
  cidr_netmask=24 ip=192.168.122.48 op monitor interval=10s \
~~~

We want both IP addresses to avoid co-locating with each other. We add
a co-location constraint so `pgsql-ip-stby2` avoids `pgsql-ip-stby1` with a
score of `-20` (higher than the stickiness of the cluster):

~~~
# pcs constraint colocation add pgsql-ip-stby2 with pgsql-ip-stby1 -20
~~~

> **NOTE**: that means the cluster manager have to start `pgsql-ip-stby1` first
> to decide where `pgsql-ip-stby2` should start according to the new scores in
> the cluster. Also, that means that whenever you move `pgsql-ip-stby1` to
> another node, the cluster might have to stop `pgsql-ip-stby2` first and
> restart it elsewhere depending on new scores.
{: .notice}

Now, we add similar co-location constraints to define that each IP address
prefers to run on a node with a slave of `pgsql-ha`:
* colocations `with slave pgsql-ha 100` means the IP will prefer to bind with a
  slave
* colocations `with pgsql-ha 50` means that the IP will prefer to bind with a
  Master __OR__ a Standby

We give higher priority to the slaves with the `100` score, but should the
slaves be stopped, the `50` score push the IP to move to the master.

~~~
# pcs constraint colocation add pgsql-ip-stby1 with slave pgsql-ha 100
# pcs constraint order start pgsql-ha then start pgsql-ip-stby1 kind=Mandatory

# pcs constraint colocation add pgsql-ip-stby2 with slave pgsql-ha 100
# pcs constraint order start pgsql-ha then start pgsql-ip-stby2 kind=Mandatory

# pcs constraint colocation add pgsql-ip-stby1 with pgsql-ha 50
# pcs constraint colocation add pgsql-ip-stby2 with pgsql-ha 50
~~~
