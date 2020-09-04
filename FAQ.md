---
layout: default
title: PostgreSQL Automatic Failover - FAQ
---

# Frequently Asked Questions

* [Why a new resource agent for PostgreSQL?](#why-new-ra-for-postgresql)
* [Why perl?](#why-perl)
* [But perl is heavier!](#perl-is-heavier)
* [Why Pacemaker?](#why-pacemaker)
* [What versions?](#what-versions)
* [Will PAF protect me against data loss?](#protection-against-data-loss)
* [Pacemaker triggered a failover, and now my old primary cannot join the cluster anymore, what should I do?](#how-to-failback)


<a name="why-new-ra-for-postgresql"></a>
__Q: Why a new resource agent for PostgreSQL?__

__A__: The `resource-agents` project already has a PostgreSQL agent. This
agent supports stateless and multi-state setup of your PostgreSQL cluster,
which make its code large and complex and make it a bit confusing and
complicated to setup, with 32 parameters.

On top of this, because PostgreSQL did not support clean demote by this time,
the RA tries hard to match PostgreSQL capabilities to Pacemaker requirement with
complicated workarounds which makes it hard to manage. A lot boils down to the
lock file requirement to protect the cluster against corruption after a demote.
Because of it, you __must__ respect a strict stop/start order of the nodes and
you can not swap the `Master` role between nodes (let's call that a
"switchover").

Moreover, the existing PostgreSQL agent takes control over the PostgreSQL
configuration file through initial configuration and adjust it to the
situation.

Our main objective was to write a new resource agent much simpler, with a code
as simple as possible, with low Pacemaker setup requirement, as close to
PostgreSQL current capabilities, non intrusive, easier and as robust as
possible. PAF supports start/stop of any node in the cluster without blowing up
everything else. It supports switchover without headache.

Being PostgreSQL DBA's, we prefer to take care of PostrgeSQL's setup ourselves
and knowing the resource agent is not messing with setup or internal mechanisms.
This make the Pacemaker setup much simpler and the PostgreSQL configuration
much more flexible to the cluster topology.


<a name="why-perl"></a>
__Q: Why perl?__

__A__: Let's answer "why not bash?" first

We started this project with bash. Bash can be a powerful language and it is
possible to make clean code with it. This is the perfect language for sysadmin.
But some limitation inherent to the language convinced us to switch to a much
advanced language.

One of the limitation is the need to call `su`, `sudo` or
`runuser` to run commands as non-privileged user, eg. starting the PostgreSQL
daemon. It seems to us much more logical, clean, lighter and safe to use
setiud/setgid to drop privileges and execute the daemon. At least, it doesn't
require to mess with `PAM` or `systemd` in some environment setup.

Moreover, the language is much cleaner to read and offer more control structures
and capabilities than bash. For complex and "large" project, we prefer to use
something else than bash.

Why Perl ? Because we know perl. We could have used python, ruby, perl6,
javascript, whatever-you-prefer, but we are just more comfortable with perl. No
other arguments.


<a name="perl-is-heavier"></a>
__Q: But perl is heavier!__

__A__: Just a bit more. Not that much. It's not 10x the memory usage by bash.

Oh wait, by the way, did you see a lot of fencing agent are written in python or
perl? Amongs the `/usr/sbin/fence_*` scripts on my system, I can find:

```
      1 #!/bin/bash
     15 #!/usr/bin/perl
     25 #!/usr/bin/python
```


<a name="why-pacemaker"></a>
__Q: Why Pacemaker?__

__A__: Pacemaker is the industry reference for high availability under Linux
systems.

It is highly reliable, configurable, and supports many topologies, so it makes
sense to benefit from its well tested features, instead of reinventing
something that already works well.


<a name="what-versions"></a>
__Q: What versions?__

__A__: PAF is designed to work with PostgreSQL 9.3 and higher.

About Pacemaker, we tested in various configurations, the stacks available
on the following systems are confirmed to work with PAF:

  * CentOS / RHEL 6 (PAF v1.x)
  * CentOS / RHEL 7 (PAF v2.x)
  * Debian 8 (PAF v2.x)


<a name="protection-against-data-loss"></a>
__Q: Will PAF protect me against data loss?__

__A:__ No, PAF will not do that.

The whole point of a resource agent is to automate the failover process, thus
minimizing the RTO (Recovery Target Objective).
__By design__, PAF does not interfere with your PostgreSQL's configuration, it
just has a minimum requirement (in short, the hot standby streaming replication
has to be enabled).
So when you configure PostgreSQL, you can choose whether you use synchronous or
asynchronous replication.
If you chose asynchronous replication (which is the default), then transactions
will be committed on the primary before they can be applied on the standbys.
In case of a failover, the most up-to-date standby will be promoted by PAF,
thus minimizing the data loss, but there will still be _some_ loss.

Service high availability (what PAF provides) and data high availability (what
PostgreSQL's synchronous replication provides) are two different concepts, and
are sometimes mutually exclusive.


<a name="how-to-failback"></a>
__Q: Pacemaker triggered a failover, and now my old primary cannot join the
cluster anymore, what should I do?__

__A__: You need to rebuild your old primary from the new primary instance first.

See the "Failover" section in the [administration page]({{ site.baseurl }}/administration.html).


