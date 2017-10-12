---
layout: default
title: PostgreSQL Automatic Failover - Cluster administration under Debian 8
---

# Cluster administration under Debian 8

In this document, we are working with cluster under Debian 8.6 using mostly
the `crm` command.

Topics:

* [Starting or stopping the cluster](#starting-or-stopping-the-cluster)
* [Swapping master and slave roles between nodes](#swapping-master-and-slave-roles-between-nodes)
* [PAF update](#paf-update)
* [PostgreSQL minor upgrade](#postgresql-minor-upgrade)
* [Adding a node](#adding-a-node)
* [Removing a node](#removing-a-node)
* [Setting up a watchdog](#setting-up-a-watchdog)
* [Forbidding a PAF resource on a node](#forbidding-a-paf-resource-on-a-node)


## Starting or stopping the cluster

To start the whole cluster, you must run the following command __on each node__:

```
# crm cluster start
```

Here is the command to stop the cluster on the local node it is executed:

```
# crm cluster stop
```

It stops or move away all the resources on the node, then stops Pacemaker and
Corosync.


To avoid moving your resources around during cluster shutdown, either put the
cluster in maintenance mode or ask the cluster to stop the resource first. Eg.:

* maintenance mode:
  
  ~~~
  # crm configure property maintenance-mode=true
  # crm cluster stop
  ~~~
* stopping the resource:
  
  ~~~
  # crm resource stop pgsql-ha
  # crm cluster stop
  ~~~
  Note that the first command will stop PostgreSQL on **all nodes**. No need to
  run it everywhere.

Don't forget on cluster start to run the opposite commands.

## Swapping master and slave roles between nodes

In this chapter, we describe how to move the master role from one node to the
other and getting back to the cluster the former master as a slave.

Here is the command to move the master role from `srv1` to `srv2`:

```
# crm resource migrate pgsql-ha srv2
# crm resource unmigrate pgsql-ha
```

That's it. Note that the former master became a slave and start replicating with
the new master.

To move the resource, `crmsh` sets an `INFINITY` constraint location for the
master on the given node. You must clear this constraint to avoid unexpected
location behavior using the ` crm resource unmigrate` command.

Note that if you do not specify the destination node, `crm` set a `-INFINITY`
score for the master resource on its current node to force it to move away:

```
# crm resource migrate pgsql-ha

# crm resource contraints pgsql-ha
    pgsql-master-ip                 (score=INFINITY, needs role=Master, id=ip-with-master)
* pgsql-ha
  : Node srv1                       (score=-INFINITY, id=cli-ban-pgsql-ha-on-srv1)

# crm resource unmigrate pgsql-ha

# crm resource contraints pgsql-ha
    pgsql-master-ip                 (score=INFINITY, needs role=Master, id=ip-with-master)
* pgsql-ha
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
# crm configure property maintenance-mode=true
# wget 'https://github.com/ClusterLabs/PAF/releases/download/v2.2.0/resource-agents-paf_2.2.0-2_all.deb'
# dpkg -i resource-agents-paf_2.2.0-2_all.deb
# crm configure property maintenance-mode=false
```

That's it, you are done.

### Keep cluster's hands off PostgreSQL resources while updating PAF

If putting the whole cluster is not an option to you, you must ask the
cluster to only ignore and avoid your PostgreSQL resources. The cluster
will still be in charge of other resources.

Considers the PostgreSQL multistate resource is called `pgsql-ha`.

First forbid the cluster resource manager to react on unexpected status by
putting the resource in unmanaged mode:

```
# crm resource unmanage pgsql-ha
```

Notice `(unmanaged)` appeared in `crm_mon` and we find the meta
attribute `is-managed=false` in the `pgsql-ha` configuration:

```
# crm configure show pgsql-ha
ms pgsql-ha pgsqld \
    meta master-max=1 master-node-max=1 clone-max=3 clone-node-max=1 notify=true is-managed=false target-role=Master
```

Now, we need to stop the recurring operations so the Local Resource Manager will
not run a command during the update. In our demo, the only recurring commands we
have are the two monitor commands (operations with an interval greater than 0
in `crm configure show pgsqld`):

```
# crm configure show pgsqld
primitive pgsqld pgsqlms \
    params pgdata="/etc/postgresql/9.3/main" datadir="/var/lib/postgresql/9.3/main" bindir="/usr/lib/postgresql/9.3/bin" pghost="/var/run/postgresql" recovery_template="/etc/postgresql/9.3/main/recovery.conf.pcmk" \
    op monitor role=Master interval=9s \
    op monitor role=Slave interval=10s \
    op start timeout=60s interval=0 \
    op stop timeout=60s interval=0 \
    op promote timeout=30s interval=0 \
    op demote timeout=120s interval=0 \
    op notify timeout=60s interval=0
```

Edit these operations in your favorite editor using:

```
# crm configure edit pgsqld
[...]
    op monitor role=Master interval=9s enabled=false
    op monitor role=Slave interval=10s enabled=false
[...]
```

Now, update PAF, eg.:

```
# wget 'https://github.com/ClusterLabs/PAF/releases/download/v2.2.0/resource-agents-paf_2.2.0-2_all.deb'
# dpkg -i resource-agents-paf_2.2.0-2_all.deb
```

We can now enable the recurrent actions:

```
# crm configure edit pgsqld
[...]
    op monitor role=Master interval=9s enabled=true
    op monitor role=Slave interval=10s enabled=true
[...]
```

Monitor action should be executed immediately and report no errors. Check that
everything is running correctly in `crm_mon` and your log files.

We can now put the resource in `managed` mode again:

```
# crm resource manage pgsql-ha
```


## PostgreSQL minor upgrade

This chapter explains how to do a minor upgrade of PostgreSQL on a two node
cluster. Nodes are called `srv1` and `srv2`, the PostgreSQL HA resource is
called `pgsql-ha`. Node `srv1` is hosting the master.

The process is quite simple: upgrade the standby first, move the master
role and finally upgrade PostgreSQL on the former PostgreSQL master node.

Here is how to upgrade PostgeSQL on the standby side:

```
# apt-get --download-only install postgresql-9.3 postgresql-contrib-9.3 postgresql-client-9.3
# crm --wait resource ban pgsql-ha srv2
# apt-get install postgresql-9.3 postgresql-contrib-9.3 postgresql-client-9.3
# crm --wait resource unban pgsql-ha
```

Here are the details of these commands:

- download all the required packages
- ban the `pgsql-ha` resource __only__ from `srv2`, effectively stopping it
- upgrade the PostgreSQL packages
- allow the `pgsql-ha` resource to run on `srv2`, effectively starting it

Now, we can move the PostgreSQL master resource to `srv2`, then take care
of `srv1`:

```
# crm --wait resource migrate pgsql-ha srv2
# apt-get --download-only install postgresql-9.3 postgresql-contrib-9.3 postgresql-client-9.3
# crm --wait resource ban pgsql-ha srv1
# apt-get install postgresql-9.3 postgresql-contrib-9.3 postgresql-client-9.3
# crm resource unmigrate pgsql-ha
```

Minor upgrade is finished. Feel free to move your master back to `srv1` if you
really need it.



## Adding a node

In this chapter, we add server `srv3` hosting a PostgreSQL standby instance as a
new node in an existing two node cluster.

Setup everything so PostgreSQL can start on `srv3` as a slave and enter in
streaming replication. Remember to create the recovery configuration template
file, setup the `pg_hba.conf` file etc.

> __NOTE__: Put the cluster in maintenance mode or use crm_simulate if you are
> afraid that some of your resources move all over the place when the new node
> appears
{: .notice}

On __all the nodes__, edit the `/etc/corosync/corosync.conf` file:

* Add the new node to the `nodelist` block
  
  ~~~
  nodelist {
        [...]
        node {
                ring0_addr: srv3
        }
  }
  ~~~
  > __NOTE__: do not forget parameter `ring1_addr` if corosync is set up to use
  > multiple network for redundancy.
  {: .notice}
* In the `quorum` block, remove the `two_node` parameter and adjust the
  `expected_votes`:
  
  ~~~
  quorum {
    provider: corosync_votequorum
    expected_votes: 3
  }
  ~~~

> __WARNING__:Again, make sure your `/etc/corosync/corosync.conf` files are
> exactly the same on **all** the nodes.
{: .warning}

Reload the corosync configuration on all the nodes if needed (it shouldn't, but
it doesn't hurt anyway):

```
# corosync-cfgtool -R
```

Fencing is mandatory. See: [http://clusterlabs.github.com/PAF/fencing.html]({{ site.baseurl }}/fencing.html).
Either edit the existing fencing resources to handle the new node if applicable,
or add a new one being able to do it. In the example, we are using
the `fence_virsh` fencing agent to create a dedicated fencing resource able to
only fence `srv3`:

```
crm conf<<EOC
primitive fence_vm_srv3 stonith:fence_virsh                   \
  params pcmk_host_check="static-list" pcmk_host_list="srv3"  \
         ipaddr="192.168.122.1" login="<username>"            \
         identity_file="/root/.ssh/id_rsa"                    \
         port="srv3-d8" action="off"                          \
  op monitor interval=10s
location fence_vm_srv3-avoids-srv3 fence_vm_srv3 -inf: srv3
EOC
```

We can now start the cluster on `srv3`!

```
# crm cluster start
```

After some time checking cluster using `crm_mon` or `crm status`, you should
find of `srv3` appearing in the cluster.

If your PosgreSQL standby is not started on the new node, maybe the cluster has
been setup with a hard `clone-max` value. Check with:

```
# crm resource meta pgsql-ha show clone-max
```

If you get a value either:
* remove it if you don't mind having a clone on each node:
  
  ~~~
  # crm resource meta pgsql-ha delete clone-max
  ~~~
* set it to the needed value:
  
  ~~~
  # crm resource meta pgsql-ha set clone-max 3
  ~~~

Your standby instance should start shortly.


## Removing a node

This chapter explains how to remove a node called `srv3` from a three node
cluster.

The first command will put the node in standby. It stops __all__ resources on
the node:

```
# crm node standby srv3
```

Next command simply remove the node from the cluster. It stops Pacemaker
on `srv3̀`, remove the cluster setup from it and reconfigure other nodes:

```
# crm cluster remove srv3
INFO: Remove node from cluster
INFO: Nodes: srv3, srv2, srv1
OK: Check nodes
OK: Validate parameters
OK: Remove node from cluster
```

On __all the nodes__, edit the `/etc/corosync/corosync.conf` file:

* remove the old node from the `nodelist` block
  
  > __NOTE__: do not forget parameter `ring1_addr` if corosync is set up to use
  > multiple network for redundancy.
  {: .notice}
* In the `quorum` block, set the `two_node` parameter if you cluster has only
  two nodes left and adjust the `expected_votes`:
  
  ~~~
  quorum {
    provider: corosync_votequorum
    two_node: 1
    expected_votes: 2
  }
  ~~~

> __WARNING__:Again, make sure your `/etc/corosync/corosync.conf` files are
> exactly the same on **all** the nodes.
{: .warning}

Reload the corosync configuration on all the nodes if needed (it shouldn't, but
it doesn't hurt anyway):

```
# corosync-cfgtool -R
```

If you choose to set a specific `clone-max` attribute to the `pgsql-ha`
resource, update it. You **don't** need to update it if it is not set (see
previous chapter).

```
# crm resource meta pgsql-ha set clone-max 2
```

## Setting up a watchdog

First, read [the watchdog chapter]({{ site.baseurl }}/fencing.html#using-a-watchdog-device)
of the "How to fence your node" documentation page for some theory.

We now explain how to setup a watchdog device as a fencing method in
Pacemaker. The `i6300esb` watchdog "hardware" has been added to the virtual
machines in our demo cluster. This hardware is correctly discovered on boot by
the kernel:

~~~
# journalctl -b|grep i6300esb 
août 09 10:36:50 srv2 kernel: i6300esb: Intel 6300ESB WatchDog Timer Driver v0.05
août 09 10:36:50 srv2 kernel: i6300esb: initialized (0xffffc900000fa000). heartbeat=30 sec (nowayout=0)
~~~

> **NOTE**: in your test environment, you could use a software watchdog from the
> Linux kernel called `softdog`. This is fine as far as this is just for demo
> purpose or very last possible solution. You should definitely rely on a
> hardware watchdog which is not tied to the operating system.
{: .notice}

Install and enable `sbd`. This small deamon is the glue between the watchdog
device and the inter-communication with Pacemaker:

~~~
# apt-get install sbd
# systemctl enable sbd.service
~~~

Edit `/etc/default/sbd` and make sure you have:

* the parameter `SBD_PACEMAKER=true` uncommented
* the parameter `SBD_WATCHDOG_DEV` pointing to the correct device

A watchdog device can only be handled by one process. Under Debian, Corosync
has been compiled with watchdog support and steal the watchdog device before
sbd can catch it, leading to a failure during sbd start:

~~~
# journalctl -u corosync|grep WD
août 09 10:38:29 srv1 corosync[778]: [WD    ] The Watchdog timeout is 6 seconds
août 09 10:38:29 srv1 corosync[778]: [WD    ] The tickle timeout is 3000 ms
août 09 10:38:29 srv1 corosync[778]: [WD    ] Watchdog /dev/watchdog is now been tickled by corosync.
août 09 10:38:29 srv1 corosync[778]: [WD    ] i6300ESB timer
août 09 10:38:29 srv1 corosync[778]: [WD    ] The Watchdog timeout is 6 seconds
août 09 10:38:29 srv1 corosync[778]: [WD    ] The tickle timeout is 3000 ms
août 09 10:38:29 srv1 corosync[778]: [WD    ] resource load_15min missing a recovery key.
août 09 10:38:29 srv1 corosync[778]: [WD    ] resource memory_used missing a recovery key.
août 09 10:38:29 srv1 corosync[778]: [WD    ] no resources configured.

# grep -E 'sbd.*error' /var/log/syslog 
Aug  9 10:38:29 srv1 sbd[25998]:    error: watchdog_init: Cannot open watchdog device '/dev/watchdog': Device or resource busy (16)
~~~

We need to deactivate watchdog from Corosync:

~~~
# crm corosync edit
~~~

Add the following block at the end of your configuration:

~~~
resources {
    watchdog_device: off
}
~~~

Synchronize the corosync configuration on all nodes:

~~~
# crm corosync push
~~~

We can now restart the cluster to set everything up. The watchdog capability
is detected by the cluster manager on each node during the cluster startup. Run
on one of the nodes:

~~~
# crm resource stop pgsql-ha
# crm cluster run "crm cluster stop"
~~~

Start the cluster:

~~~
# crm cluster start
# ssh srv2 crm cluster start
# ssh srv3 crm cluster start
~~~

After some seconds, the following equivalent commands should return true:

~~~
# crm configure show | grep have-watchdog
 have-watchdog: true \

# crm_attribute -qn have-watchdog
true
~~~

Adjust the `stonith-watchdog-timeout` cluster property:

~~~~
# crm configure property stonith-watchdog-timeout=10s
~~~~

A good value for `stonith-watchdog-timeout` is the double
of `SBD_WATCHDOG_TIMEOUT` (set in `/etc/default/sbd`) or sbd parameter `-1`
(set in parameter `SBD_OPTS` in `/etc/default/sbd`) which is set by default to
5 seconds .

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
# crm configure location forbid-pgsqlha-on-srv3 pgsql-ha resource-discovery=never rule -inf: \#uname eq srv3
```

This creates constraint location associated to a rule allowing us to
avoid ( `score=-INFINITY` ) the node `srv3` ( `\#uname eq srv3` ) for
resource `pgsql-ha`. The `resource-discovery=never` is mandatory here as it
forbid the "probe" action the CRM is usually running to discovers the state of
a resource on a node. On a node where your PostgreSQL cluster is not running,
this "probe" action will fail, leading to bad cluster reactions.
