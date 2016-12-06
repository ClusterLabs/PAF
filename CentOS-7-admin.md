---
layout: default
title: PostgreSQL Automatic Failover - Cluster administration under CentOS 7
---

# Cluster administration under CentOS 7

In this document, we are working with cluster under CentOS 7.2 using mostly
the `pcs` command. It supposes that the `pcsd` deamon is enabled and running and
authentication between node is set up (see quick start).

## Start/Stop of the cluster

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

## Adding a node

In this chapter, we add server `srv3` hosting a PostgreSQL standby instance as a
new node in an existing two node cluster.

Setup everything so PostgreSQL can start on `srv3` as a slave and enter in
streaming replication. Remember to create the recovery configuration template
file, setup the `pg_hba.conf` file etc.

On this new node, setup the pcsd deamon and its authentication:

```
passwd hacluster
systemctl enable pcsd
systemctl start pcsd
pcs cluster auth srv1 srv2 srv3 -u hacluster
```

On all other nodes, authenticate to the new node:

```
pcs cluster auth srv3 -u hacluster
```

We are now ready to add the new node.

> Put the cluster in maintenance mode or use crm_simulate if you are afraid
> that some of your resources move all over the place when the new node appears
{: .notice}

```
pcs cluster node add srv3
```

> If corosync is set up to use multiple network for redundancy, use the
> following command:
>
> ```
> pcs cluster node add srv3,srv3-alt
> ```
{: .notice}

Reload the corosync configuration on all the nodes if needed (it shouldn't, but
it doesn't hurt anyway):

```
pcs cluster reload corosync
```

Fencing is mandatory. See: [http://dalibo.github.com/PAF/fencing.html]({{ site.baseurl }}/fencing.html).
Either edit the existing fencing resources to handle the new node if applicable,
or add a new one being able to do it. In the example, we are using
the `fence_virsh` fencing agent to create a dedicated fencing resource able to
only fence `srv3`:

```
pcs stonith create fence_vm_srv3 fence_virsh pcmk_host_check="static-list" pcmk_host_list="srv3" ipaddr="192.168.122.1" login="<username>" port="srv3-c7" action="off" identity_file="/root/.ssh/id_rsa"
pcs constraint location fence_vm_srv3 avoids srv3=INFINITY
```

We can now start the cluster on `srv3`!

```
pcs cluster start
```

After some time checking the integration of `srv3` in the cluster using `crm_mon`
or `pcs status`, you probably find that your PosgreSQL standby is not started on
the new node. We actually need to allow one more clone in the cluster:

```
pcs resource meta pgsql-ha clone-max=3
```

Your standby instance should start shortly.

## Removing one node under CentOS 7

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

The last command change the maximum clone allowed in the cluster:

```
pcs resource meta pgsql-ha clone-max=2
```

## Forbidding a PAF resource  on a node

In this chapter, we need to set up a node where no PostgreSQL instance of your
cluster is supposed to run. That might be that PostgreSQL is not installed on
this node, the instance is part of a different resource cluster, etc.

The following command forbid your multi-state PostgreSQL resource
called `pgsql-ha` to run on node called `srv3`:

```
pcs constraint location pgsql-ha rule resource-discovery=never score=-INFINITY \#uname eq srv3
```

This creates constraint location associated to a rule allowing us to
avoid ( `score=-INFINITY` ) the node `srv3` ( `\#uname eq srv3` ) for
resource `pgsql-ha`. The `resource-discovery=never` is mandatory here as it
forbid the "probe" action the CRM is usually running to discovers the state of
a resource on a node. On a node where your PostgreSQL cluster is not running,
this "probe" action will fail, leading to bad cluster reactions.
