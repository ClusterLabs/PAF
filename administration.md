---
layout: default
title: PostgreSQL Automatic Failover - Installation
---

# Administration

This manual gives an overview of the tasks you can expect to do when using PAF
to manage PostgreSQL instances for high availability, as well as several useful
commands.

## A word of caution

Pacemaker is a complex and sensitive tool.
Before running any command modifying an active cluster configuration, you
should always validate its effect beforehand by using the `crm_shadow` and
`crm_simulate` tools.

## Pacemaker command line tools

The Pacemaker-related actions documented on this page use exclusively generic
Pacemaker commands.

Depending on the Pacemaker stack you're using, you may have an additionnal
command line administration tool installed (usually, `pcs` or `crmsh`).
If that's the case, you should obviously use the tool that you're the most
comfortable with.


## Pacemaker maintenance mode

Pacemaker provides commands to put several resources or even the whole cluster
in maintenance mode, meaning that the "unmanaged" resources will not be
monitored anymore, and changes to their status will not trigger any automatic
action.

If you're about to do something that may impact Pacemaker (reboot a PostgreSQL
instance, a whole server, change the network configuration, etc.), you should
consider using it.
Refer to the official Pacemaker's documentation related to your installation
for the specific commands.


## Administrating a PAF managed PostgreSQL instance

If your PostgreSQL instance is managed by Pacemaker, you should proceed to
administration tasks with care.

Especially, if you need to restart a PostgreSQL instance, you should first put
the resource in maintenance mode, so Pacemaker will to attempt to automatically
restart it.

Also, you should refrain to use any tool other than `pg_ctl` (provided with any
PostgreSQL installation) to start and stop your instance if you need to
"Other tools" may include any conveniance wrapper, like SysV init scripts,
systemd unit files, or `pg_ctlcluster` Debian wrapper.
Pacemaker only uses `pg_ctl`, and as other tools behave differently, using them
could lead to some easy mistakes, like an init script reporting that the
instance is stopped when it is not.



## Manual switchover

Depending on your configuration, and most notably on the constraints you set up
on the nodes for your resources, Pacemaker may trigger automatic switchover of
the resources.

If required, you can also ask it to do a manual switchover, for example before
doing a maintenance operation on the node hosting the master resource.

These steps use only Pacemaker commands to move the master PostgreSQL resource
around.
Note that in these examples, we only ask for Pacemaker to move the "master"
resource. That means that, based on your configuration, the following should
happen:

  * the current master PostgreSQL resource is demoted
  * another PostgreSQL resource, running previously as a slave resource, will
    be promoted
  * any resource using a collocation constraint with the master resource (like
    a Pacemaker controlled IP address) will also be affected

### Move the master resource to another node

```
    crm_resource --move --master --resource <PAF_resource_name> --host <target_node>
```

This command will set up an `INFINITY` score ont the target node for the master
resource.
This will force Pacemaker to trigger the switchover to the target node:

  * "demote" PostgreSQL resource on the current master node ("stop" the
    resource, and then "start" it as a "slave" resource)
  * "promote" PostgreSQL resource on the target node


### Ban the master resource from a node

```
    crm_resource --ban --master --resource <PAF_resource_name>
```

This command will set up a `-INFINITY` score on the node currently running the
master resource.
This will force Pacemaker to trigger the switchover to another available node:
  * "demote" PostgreSQL resource on the current master node ("stop" the
    resource, and then "start" it as a "slave" resource)
  * "promote" PostgreSQL resource on another node


### Clear the constraints after the switchover

Unless you used the `--lifetime` option of `crm_resource`, the scores set up by
the previous commands will not be automatically removed.
__This means that unless you remove these scores manually, your master resource
is now stuck on one node (`--move` case), or forbidden on one node (`--ban` 
case).__
So, for your cluster to be fully operational again, you have to clear these
scores.
The following command will remove any constraint set by the previous commands:

```
    crm_resource --clear --master --resource <PAF_resource_name>
```

Note that depending on your configuration, the `--clear` action may trigger
another switchover (for example, if you set up a preferred node for the master
resource).
Before running such a command (or really, _any command_ modifying your cluster
configuration), you should always validate its effect beforehand by using the
`crm_shadow` and `crm_simulate` tools.


## Failover

That's it, there was a problem with the node hosting the primary PostgreSQL
instance, and your cluster triggered a failover.
That means one of the standy instances has been promoted, is now a primary
PostgreSQL instance, running as the `master` resource, and the high
availability IP address has been moved to this node.
That's exactly for this situation that you installed Pacemaker and PAF, so far
so good.

Now, what needs to be done ?

### Verify everything, fix every problem found

Hopefully, [you did configure a reliable fencing device]({{ site.baseurl }}/fencing.html),
so the failing node has been completely disconnected from the cluster.
From this point, first you need to investigate on the origin of failure, and
fix whatever may the problem be. At this point, you usually look for network,
virtualization or hardware issues.

Once that's done, you connect to your fenced node, and __before you do 
anything__ (including un-fence it if your fencing method involves network
isolation only), you ensure that Corosync, Pacemaker and PostgreSQL processes
are down: you certainly don't want these to suddently kick in your alive
cluster!
Then, again, you check everything for errors related to the failure.
Good starting points are the OS, Pacemaker and PostgreSQL log files.
If you find something that went wrong, fix it before moving to the next step.

### Rebuild the failed PostgreSQL instance

Finally, __you need to rebuild the PostgreSQL instance on the failed node__.
That's right, as the PostgreSQL resource suffered a failover, it is very likely
that the promoted PostgreSQL instance was late by a few transactions.

  * the first consequence is that you did lose several commited transactions,
    hopefully not that many
  * the second consequence is that your old primary is too advanced in the
    transaction log to come back as a standby as it is

So you need to rebuild your old, failed primary instance, based on the one
currently used as the master resource.
To do this, use any backup and recovery method that fits your configuration.
PostgreSQL's `pg_basebackup` tool may be handy if your instance is not too
big, and if you're in PostgreSQL 9.5+, you may want to consider `pg_rewind`.
If you're not familiar with all this rebuild thing, you should refer to the
PostgreSQL's documentation, __before you even consider using the PAF agent__.
Obviously, waiting for a failover to happen before considering what needs to
be done in that case is not a good idea.

Beware when you do your rebuild not to erase local files with a content
specific to that node (at the very least, avoid erasing `recovery.conf.pcmk`
and `pg_hba.conf` files content).

The only exception to that "rebuild" rule is if you were only using
PostgreSQL's synchronous replication at the time of the failover (and the
synchronous standby was the one promoted, which would be the case unless it
__also__ suffered from a failure).

Once you have rebuilt your instance from the running master PostgreSQL
resource, verify that you can successfully start it as a standby (remember
to create the `recovery.conf` file in the instance's `PGDATA` directory
before starting it).

### Reintroduce the node in the cluster

Then, it's time to reintroduce your failed node in the cluster.

__But before you actually do that__, use the nice `crm_simulate` command with
the `--node-up` option to do a _dry run_ from an active node of the cluster.

If the cluster seems to keep its sanity based on the `crm_simulate` output,
then you can bring Corosync and Pacemaker processes up on the previously failed
node, and you're finally done!

Note that you may have to clear previous errors (`failcounts`) before Pacemaker
considers your rebuilt PostgreSQL instance as a sane resource.

### That's it!

In conclusion, remember that PostgreSQL Automatic Failover resource agent does
not rebuild a failed instance for you, nor does it do anything that may alter
your data or your configuration.

So you need to be prepared to deal with the failover case, by documenting your
configuration and the actions required to bring a failed node up.


### Full failover example

Here is a full example of a failover.

Consider the following situation:

  * node `srv1` runs PAF master resource (primary PostgreSQL instance and
    Pacemaker's managed IP)
  * nodes `srv2` and `srv3` run PAF slave resources (standby PostgreSQL
    instances, connected to the primary using streaming replication)

The node `srv1` becomes unresponsive - let's say that someone messed up with the
firewall rules, so the node is still up, but not visible anymore to the
cluster.

Based on the quorum situation, Pacemaker triggers the following actions:

  * fence the `srv1` node (as you can imagine, in this situation your STONITH
    device should not try to connect to the node it has to fence, that's part
    of fencing's configuration good practices)
  * as soon as `srv1` has been fenced (say, physically powered off), promote
    the standby that is the most advanced in transaction replay (`srv2` for the
    example).

From this point, your cluster is in this situation:

  * node `srv1` is powered off, and marked as `offline` in the cluster
  * node `srv2` runs PAF master resource (primary PostgreSQL instance and
    Pacemaker's managed IP)
  * nods `srv3` runs PAF slave resource (standby PostgreSQL instance, connected
    to the primary using streaming replication)

Only two nodes are now alive in the quorum, so the lost of any new member would
bring the whole cluster down.
You don't want things to stay that way too long, so you'll have to bring `srv1`
up again:

  * you power it on
  * as Corosync, Pacemaker and PostgreSQL has been configured not to start
    automatically, they don't
  * you connect to the `srv1` server and correct the firewall problem
  * you rebuild the PostgreSQL instance on `srv1`, for example using the 
    `pg_basebackup` PostgreSQL tool, ensuring you don't erase the
    `recovery.conf.pcmk` and `pg_hba.conf` files

Now, `srv1` is clean, and you can consider integrating it back in the cluster.
Go to another node, like `srv2`, and check the cluster reaction if `srv1`
member was to be up again :
```
    crm_simulate -SL --node-up srv1
```

This should print something like this:

  * first, the actual cluster state:
```
    Current cluster status:
    Online: [ srv2 srv3 ]
    OFFLINE: [ srv1 ]
    
     fence_vm_srv1       (stonith:fence_virsh):  Started srv2
     fence_vm_srv2       (stonith:fence_virsh):  Started srv3
     fence_vm_srv3       (stonith:fence_virsh):  Started srv2
     Master/Slave Set: pgsql-ha [pgsqld]
         Masters: [ srv2 ]
         Slaves: [ srv3 ]
         Stopped: [ srv1 ]
     pgsql-master-ip        (ocf::heartbeat:IPaddr2):       Started srv2
```

  * then, the modifications you asked to be simulated, and the cluster reaction:
```
    Performing requested modifications
     + Bringing node srv1 online
    
    Transition Summary:
     * Start   pgsqld:2     (srv1)
```

  * then a more detailed list of the cluster actions we'll skip here, and at
    the end the expected final cluster state:
```
    Revised cluster status:
    Online: [ srv1 srv2 srv3 ]
    
     fence_vm_srv1       (stonith:fence_virsh):  Started srv2
     fence_vm_srv2       (stonith:fence_virsh):  Started srv3
     fence_vm_srv3       (stonith:fence_virsh):  Started srv2
     Master/Slave Set: pgsql-ha [pgsqld]
         Masters: [ srv2 ]
         Slaves: [ srv1 srv3 ]
     pgsql-master-ip        (ocf::heartbeat:IPaddr2):       Started srv2
```

That seems good!
So now you just need to really start Corosync and Pacemaker on `srv1`, and if
everythings goes as planned, you're done.




