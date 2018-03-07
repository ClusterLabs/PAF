---
layout: default
title: PostgreSQL Automatic Failover - Quick start Debian 8
---

# Quick Start Debian 8

The Debian HA team missed the freeze time of Debian 8 (Jessie). They couldn't
publish the Pacemaker, Corosync and related packages on time. They did publish
them later in Debian 9 (strecth) and backport them officially for Debian 8.

This quick start tutorial is based on Debian 8.9 and only explains how to
install the Pacemaker stack. Other steps are detailed in the quick start
tutorial for Debian 9.

Setup the backport repository to install the Pacemaker stack under Debian 8
(adapt the URL to your closest mirror):

```
cat <<EOF >> /etc/apt/sources.list.d/jessie-backports.list
deb http://ftp2.fr.debian.org/debian/ jessie-backports main
EOF
```

About PostgreSQL, this tutorial uses the PGDG repository maintained by the
PostgreSQL community (and actually Debian maintainers). Here is how to add it:

```
cat <<EOF >> /etc/apt/sources.list.d/pgdg.list
deb http://apt.postgresql.org/pub/repos/apt/ jessie-pgdg main
EOF
```

Now, update your local cache:

```
apt-get update
apt-get install pgdg-keyring
```

Depending on the tool you want to use, you can follow up with next steps from
chapter "Network setup" in the
["Quick Start Debian 9 using crm"]({{ site.baseurl}}/Quick_Start-Debian-9-crm.html#network-setup)
documentation page or the
["Quick Start Debian 9 using pcs"]({{ site.baseurl}}/Quick_Start-Debian-9-pcs.html#network-setup)
one.
