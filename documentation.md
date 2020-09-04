---
layout: default
title: PostgreSQL Automatic Failover - Documentation
---

# Documentation

## Frenquently Asked Questions

See the [FAQ]({{ site.baseurl }}/FAQ.html) page.

## Installation

See the [Installation]({{ site.baseurl }}/install.html) page.

## Configuration

See the [Configuration]({{ site.baseurl }}/configuration.html) page.

## Administration

* general: see the [Administration]({{ site.baseurl }}/administration.html)
  page.
* [Administration cookbook with CentOS 7]({{ site.baseurl }}/CentOS-7-admin-cookbook.html) (using `pcs`)
* [Administration cookbook with Debian 8]({{ site.baseurl }}/Debian-8-admin-cookbook.html) (using `crm`)

## Fencing

We wrote a page about how badly you need to be able to fence your nodes in your
cluster and how to do it. See:
[How to fence your node]({{ site.baseurl }}/fencing.html)

## Quick starts

Quick starts are tutorials explaining how to install and setup a PostgreSQL
cluster in high availability using the PAF project.

Their purpose is to help you to build your first cluster to experiment with. It
does *not* implement various good practices related to your system, Pacemaker
or PostgreSQL. These quick start alone are not enough. During your journey in
building a safe HA cluster, you must train about security, network, PostgreSQL,
Pacemaker, PAF, etc. In regard with PAF, make sure to read carefully
documentation from <https://clusterlabs.github.io/PAF/documentation.html>.

We currently provide the following quick starts:

  * [quick start with CentOS 6]({{ site.baseurl }}/Quick_Start-CentOS-6.html)
  * [quick start with CentOS 7]({{ site.baseurl }}/Quick_Start-CentOS-7.html)
  * [quick start with CentOS 8]({{ site.baseurl }}/Quick_Start-CentOS-8.html)
  * [quick start with Debian 8]({{ site.baseurl }}/Quick_Start-Debian-8.html)
  * [quick start with Debian 8 in a two node cluster]({{ site.baseurl }}/Quick_Start-Debian-8-two_nodes.html)
  * [quick start with Debian 9 using crm]({{ site.baseurl }}/Quick_Start-Debian-9-crm.html)
  * [quick start with Debian 9 using pcs]({{ site.baseurl }}/Quick_Start-Debian-9-pcs.html)
  * [quick start with Debian 10 using pcs]({{ site.baseurl }}/Quick_Start-Debian-10-pcs.html)

