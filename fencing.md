---
layout: default
title: PostgreSQL Automatic Failover - Fencing
---

#How to fence your cluster nodes

This tutorial aims to describe various fencing techniques.

Fencing is one of the mandatory piece you need when building an high available
cluster for your database. Let's reword this: you **MUST** have a fencing
method in your database cluster. And if this is still not clear enough, let's
quote [Alteeve](https://alteeve.ca/w/AN!Cluster_Tutorial_2#Concept.3B_Fencing)
guys:

> Warning: DO NOT BUILD A CLUSTER WITHOUT PROPER, WORKING AND TESTED FENCING.
> Fencing is a absolutely critical part of clustering. Without fully working
> fence devices, your cluster will fail.

Fencing is the ability to isolate a node from the cluster. It can be done in
various way:

  * I/O fencing: interrupt network access, SAN access through Fibre channel, etc
  * Power fencing: using an UPS, PDU, embeded IPMI

With the advent of virtualization, we could add another kind of fencing where
the VM ask the hypervisor to force-shutdown one of its relative.

Should an issue happen where the master does not answer to the cluster,
successful fencing is the only way to be sure what is its status: shutdown or
not able to accept new work or touch data. It avoid countless situations where
you end up with a split brain scenarios or data corruption.

If one scenario exists where a corruption or split brain is possible in your
architecture it __WILL__ happen, soon or later. At this time, your high
available cluster will become your worst enemy, interrupting your service way
much more than with a manual failovers.

Fencing agents are available for most Linux distribution as a package named
`fence-agents`. As soon as you have a fencing agent working you just have
to instruct your cluster how to use them. See the Quick start guides about this
part.

##Virtual fencing using libvirtd and virsh

This is the easier fencing method when testing your cluster in a virtualized
environment. It relies on the fencing agent called "fence_virsh". This tutorial
has been written using a Debian 8 as hypervisor (hv) and CentOS 6 as guests
(ha1 and ha2).

On the side hypervisor side, we need the following packages:

  * libvirt-bin
  * libvirt-clients
  * libvirt-daemon

The VMs has been created using qemu-kvm through the "virt-manager" user
interface.

After installing these packages and created your VMs, root should be able to
list them using "virsh":

```
root@hv:~# virsh list --all
 Id    Name                           State
----------------------------------------------------
 6     ha2-centos6                    running
 7     ha1-centos6                    running
```

To force stop a VM (power cord removal), you just need to run the following
command:

```
root@firost:~# virsh destroy ha1-centos6
Domain ha1-centos6 destroyed

root@firost:~# virsh list --all
 Id    Name                           State
----------------------------------------------------
 6     ha2-centos6                    running
 -     ha1-centos6                    shut off
```


Fencing agent `fence_virsh` is quite simple: it connects as root on the
hypervisor using SSH, then use virsh as you would have done to stop a VM. You
just need to make sure your VM are able to connect as root to your hypervisor.

If you don't know how to configure SSH to allow a remote connexion without
password, here is an example using `hv` (the hypervisor) and `ha1`. As root on
ha1:

```
root@ha1:~$ ssh-keygen
# [...]

root@ha1:~$ cat .ssh/id_rsa.pub | ssh root@hv "cat >>/root/.ssh/authorized_keys"
root@hv's password:

root@ha1:~$ ssh root@hv

root@hv:~#
```

Repeat for all nodes. If you SSH is properly setup, you should now be able to
use `fence_virsh` to control your VM from each of them:

```
root@ha1:~$ fence_virsh -a hv -l root -x -k /root/.ssh/id_rsa -n ha2-centos6 -o status
Status: ON

root@ha1:~$ fence_virsh -a hv -l root -x -k /root/.ssh/id_rsa -n ha2-centos6 -o on
Success: Already ON

root@ha1:~$ fence_virsh -a hv -l root -x -k /root/.ssh/id_rsa -n ha2-centos6 -o off
Success: Powered OFF

root@ha1:~$ fence_virsh -a hv -l root -x -k /root/.ssh/id_rsa -n ha2-centos6 -o status
Status: OFF

root@ha1:~$ ping -c 1 ha2
PING ha2 (10.10.10.51) 56(84) bytes of data.
From ha1 (10.10.10.50) icmp_seq=1 Destination Host Unreachable

--- ha2 ping statistics ---
1 packets transmitted, 0 received, +1 errors, 100% packet loss, time 3000ms

root@ha1:~$ fence_virsh -a hv -l root -x -k /root/.ssh/id_rsa -n ha2-centos6 -o on
Success: Powered ON

root@ha1:~$ fence_virsh -a hv -l root -x -k /root/.ssh/id_rsa -n ha2-centos6 -o status
Status: ON

root@ha1:~$ ping -c 1 ha2
PING ha2 (10.10.10.51) 56(84) bytes of data.
64 bytes from ha2 (10.10.10.51): icmp_seq=1 ttl=64 time=1.54 ms

--- ha2 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 1ms
rtt min/avg/max/mdev = 1.548/1.548/1.548/0.000 ms
```


##I/O fencing using SNMP

The fencing method allows you to shutdown an ethernet port on a manageable
switch using the SNMP protocol. This is useful to cut all accesses to the
world to your node-to-fence or its iSCSI access to datas.

The fencing agent available is `fence_ifmib`. It requires the IP address of the
switch and the ethernet port to switch off. Optionally, you might want to add
some authentication information (username/password), the SNMP version (2c by
default), the SNMP community, etc.

This following example is based on a simple and cheap D-Link DGS-1210-24 switch.
Its IP address is `192.168.1.4`, the node to fence is `ha2` and its
port number is 11.

```
root@ha1:~# ping -c 1 ha2
PING 192.168.1.101 (192.168.1.101) 56(84) bytes of data.
64 bytes from 192.168.1.101: icmp_seq=1 ttl=64 time=1.96 ms

--- 192.168.1.101 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 1.964/1.964/1.964/0.000 ms

root@ha1:~# fence_ifmib -a 192.168.1.4 -n 11 -c private -o status
Status: ON

root@ha1:~# fence_ifmib -a 192.168.1.4 -n 11 -c private -o off
Success: Powered OFF

root@ha1:~# fence_ifmib -a 192.168.1.4 -n 11 -c private -o status
Status: OFF

root@ha1:~# ping -c 1 ha2
PING 192.168.1.101 (192.168.1.101) 56(84) bytes of data.

--- 192.168.1.101 ping statistics ---
1 packets transmitted, 0 received, 100% packet loss, time 0ms

root@ha1:~# fence_ifmib -a 192.168.1.4 -n 11 -c private -o on
Success: Powered ON

root@ha1:~# fence_ifmib -a 192.168.1.4 -n 11 -c private -o status
Status: ON

root@ha1:~# ping -c 1 ha2
PING 192.168.1.101 (192.168.1.101) 56(84) bytes of data.
64 bytes from 192.168.1.101: icmp_seq=1 ttl=64 time=1.83 ms

--- 192.168.1.101 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 1.833/1.833/1.833/0.000 ms
```

__Warning__: if you are fencing a node cutting its network accessed, take great
care when you unfence it. While fenced, the node might get angry and try to
fence other node when comming back. You better want some quorum setup to keep
it under control, or switching off pacemaker before unfencing it.
