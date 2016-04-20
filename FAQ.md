---
layout: default
title: PostgreSQL Automatic Failover - FAQ
---

# Frequently Asked Questions

__Q: Why a new resource agent for PostgreSQL?__

__A__: The `resource-agents` project already have a PostgreSQL agent. This
agent supports stateless and multi-state setup of your PostgreSQL cluster,
which make its code large and complex and make it a bit confusing and complicated
to setup, with 32 parameters.

On top of this, because PostgreSQL did not support demote by this time, the RA
tries hard to match PostgreSQL capacities to Pacemaker requirement with
complicated workarounds which makes it hard to manage (eg. lock file or
strict starting order).

Moreover, the existing PostgreSQL agent takes control over the PostgreSQL
configuration file through initial configuration and adjust it to the
situation.

Our main objective was to write a new resource agent much simpler, with a code
as simple as possible, with low Pacemaker setup requirement, as close to
PostgreSQL current capabilities, non intrusive and as robust as possible.

Being PostgreSQL DBA's, we prefer to take care of PostrgeSQL's setup ourselves
and knowing the resource agent is not messing with setup or internal mechanisms.
This make the Pacemaker setup much simpler and the PostgreSQL configuration
much more flexible to the cluster topology.

__Q: Why perl?__

__A__:

FIXME

__Q: Why Pacemaker?__

__A__:

FIXME

__Q: What versions__

__A__:

FIXME
