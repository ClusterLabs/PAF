---
layout: default
title: PostgreSQL Automatic Failover - Home
---

# PostgreSQL Automatic Failover

## Intro

Thanks to Pacemaker and Corosync, PostgreSQL Automatic Failover (aka. PAF) is
able to:

  * detect a failure of your PostgreSQL instance
  * recover your primary instance...
  * ... or failover to another node
  * Select the best available standby on failover (with the smallest lag)
  * switchover roles in your cluster between your primary and a standby

Thanks to Pacemaker and Corsync, you can easily build a SAFE and ROBUST cluster
with:

  * proper fencing support
  * quorum support
  * watchdog support
  * resource group (eg. manage your resource IP for you!)


## Details

Pacemaker is nowadays the industry reference for High Availability. In the same
fashion than for Systemd, all Linux distributions moved (or are moving) to this
unique Pacemaker+Corosync stack, removing all other existing high availability
stacks (CMAN, RGManager, OpenAIS, ...). It is able to detect failure on various
services and automatically decide to failover the failing resource to another
node when possible.

To be able to manage a specific service resource, Pacemaker interact with it
through a so-called "Resource Agent". Resource agents must comply to the OCF
specification which define what they must implement (start, stop, promote,
etc), how they should behave and inform Pacemaker of their results.

PostgreSQL Automatic Failover (aka. PAF) is a new Resource Agent dedicated
to PostgreSQL. Its original wish is to keep a clear limit between the Pacemaker
administration and the PostgreSQL one, to keep things simple, documented and
yet powerful.

Once your PostgreSQL cluster built using internal streaming replication, PAF is
able to expose to Pacemaker what is the current status of the PostgreSQL
instance on each node: primary, standby, stopped, catching up, etc. Should a
failure occurs on the primary, Pacemaker will try to recover it by default.
Should the failure be non-recoverable, PAF allows the standbys to be able to
elect the best of them (the closest one to the old primary) and promote it as
the new primary. All of this thanks to the robust, feature-full and most
importantly experienced project: Pacemaker.

For information about how to install, configure and manage this agent, as well
as several Quick starts to help you getting started, see the [documentation]
page.

PAF has been tested and works with PostgreSQL 9.3 and above,  Pacemaker 1.1.x
and above. 

PAF is a free software licensed under the PostgreSQL License.

[documentation]: {{ site.baseurl }}/documentation.html

