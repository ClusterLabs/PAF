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
# wget 'https://github.com/dalibo/PAF/releases/download/v2.1.0/resource-agents-paf_2.1.0-1_all.deb'
# dpkg -i resource-agents-paf_2.1.0-1_all.deb
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
# wget 'https://github.com/dalibo/PAF/releases/download/v2.1.0/resource-agents-paf_2.1.0-1_all.deb'
# dpkg -i resource-agents-paf_2.1.0-1_all.deb
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
