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
tries hard to match PostgreSQL capabilities to Pacemaker requirement with
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

Why Perl ? Because we know perl. We could have use python, ruby, perl6,
javascript, whatever-you-prefer, but we are just more comfortable with perl. No
other arguments.


__Q: But perl is heavier!__

__A__: Just a bit more. Not that much. It's not 10x the memory usage by bash.

Oh wait, by the way, did you see a lot of fencing agent are written in python or
perl? Amongs the `/usr/sbin/fence_*` scripts on my system, I can find:

```
      1 #!/bin/bash
     15 #!/usr/bin/perl
     25 #!/usr/bin/python
```

__Q: Why Pacemaker?__

__A__:

FIXME

__Q: What versions__

__A__:

FIXME
