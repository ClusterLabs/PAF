---
layout: default
title: PostgreSQL Automatic Failover - Fencing
---

# How to fence your cluster nodes

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

- I/O fencing (aka. resource fencing): interrupt network access, SAN access 
  through Fibre channel, etc.
- Node fencing: using some power devices like an UPS, PDU, embeded IPMI

With the advent of virtualization, we could add another kind of fencing where
the VM asks the hypervisor to force-shutdown one of its relatives.

Should an issue happen where the primary does not answer to the cluster,
successful fencing is the only way to be sure what is its status: shutdown or
not able to accept new work or touch data. It avoids countless situations where
you end up with split brain scenarios or data corruption.

If one scenario exists where a corruption or split brain is possible in your
architecture it __WILL__ happen, sooner or later. At this time, your high
available cluster will become your worst enemy, interrupting your service way
much more than with a manual failovers on a human decision.

Fencing agents are available for most Linux distributions as a package named
`fence-agents`. As soon as you have a fencing agent working you just have
to instruct your cluster how to use it. See the Quick start guides for examples
about this part, or refer to the [official Pacemaker's documentation](http://clusterlabs.org/doc/).

Before giving you some examples of fencing method below, here are some more
interesting links about fencing:

- <http://clusterlabs.org/doc/crm_fencing.html>
- <http://advogato.org/person/lmb/diary/105.html>
- <https://ourobengr.com/ha/>
- <https://ourobengr.com/stonith-story/>

Fencing examples:

- [Node fencing using a PDU](#node-fencing-using-a-pdu)
- [Node fencing using libvirtd and virsh](#node-fencing-using-libvirtd-and-virsh)
- [Virtual machine fencing using Proxmox API](#virtual-machine-fencing-using-proxmox-api)
- [Resource fencing using SNMP](#resource-fencing-using-snmp)
- [Using a watchdog device](#using-a-watchdog-device)

## Node fencing using a PDU

Power fencing allows you to shutdown a node by switching off its power outlet
remotely.

The following example is based on a PDU from APC, model AP7920,
having 8 power outlets. This PDU allows you to control each outlet
independently using a web interface, telnet, ssh, SNMP v1 or SNMPv3. Its IP
address is `192.168.1.82`.

To manage it using telnet or ssh, we use the fencing agent `fence_apc`:

```
root@srv1:~# fence_apc --ssh --ip=192.168.1.82 --username=apc --password=apc --action=list-status
1,Outlet 1,ON
3,Outlet 3,ON
2,Outlet 2,ON
5,Outlet 5,ON
4,Outlet 4,ON
7,Outlet 7,ON
6,Outlet 6,ON
8,Outlet 8,ON

root@srv1:~# fence_apc --ssh --ip=192.168.1.82 --username=apc --password=apc --plug=1 --action=status
Status: ON

root@srv1:~# fence_apc --ssh --ip=192.168.1.82 --username=apc --password=apc --plug=1 --action=off
Success: Powered OFF

root@srv1:~# fence_apc --ssh --ip=192.168.1.82 --username=apc --password=apc --plug=1 --action=status
Status: OFF
```

Just remove the `--ssh` to access your APC using telnet.

To manage the same PDU using the SNMP protocol, we have to use the fence agent
`fence_apc_snmp`, eg.:

```
root@srv1:~# fence_apc_snmp --ip=192.168.1.82 --username=apc --password=apc --plug=1 --action=status
Status: OFF
root@srv1:~# fence_apc_snmp --ip=192.168.1.82 --username=apc --password=apc --plug=1 --action=on
Success: Powered ON
root@srv1:~# fence_apc_snmp --ip=192.168.1.82 --username=apc --password=apc --plug=1 --action=status
Status: ON
```


## Node fencing using libvirtd and virsh

This is the easier fencing method when testing your cluster in a virtualized
environment. It relies on the fencing agent called `fence_virsh`. This tutorial
has been written using a Debian 8 as hypervisor (`hv`) and CentOS 6 as guests
(`ha1` and `ha2`).

On the hypervisor's side, we need the following packages:

  * `libvirt-bin`
  * `libvirt-clients`
  * `libvirt-daemon`

The VMs has been created using `qemu-kvm` through the `virt-manager` user
interface.

After installing these packages and creating your VMs, root (or another system
with some more setup) should be able to list them using `virsh`:

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
root@hv:~# virsh destroy ha1-centos6
Domain ha1-centos6 destroyed

root@hv:~# virsh list --all
 Id    Name                           State
----------------------------------------------------
 6     ha2-centos6                    running
 -     ha1-centos6                    shut off
```


The fencing agent `fence_virsh` is quite simple: it connects as root (it is
possible to use a normal user with some more setup though) on the hypervisor
using SSH, then use `virsh` as you would have done to stop a VM. You just need
to make sure your VMs are able to connect as root to your hypervisor.

If you don't know how to configure SSH to allow a remote connexion without
password, here is an example using `hv` (the hypervisor) and `ha1`. As root on
`ha1`:

```
root@ha1:~$ ssh-keygen
# [...]

root@ha1:~$ ssh-copy-id root@hv
root@hv's password:

root@ha1:~$ ssh root@hv

root@hv:~#
```

Repeat for all nodes. If your SSH is properly setup, you should now be able to
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

## Virtual machine fencing using Proxmox API

If you use virtual machine hosted on Proxmox hypervisor, you can use the fencing agent
`fence_pve`.

This agent uses [Promox API](https://pve.proxmox.com/wiki/Proxmox_VE_API) to control virtual
machines or containers.

First, you should create a dedicated user with *VM.PowerMgmt*
permission ([Permission Management](https://pve.proxmox.com/wiki/User_Management#pveum_permission_management)).

In this example, the user (`hauser`) has the role *PVEVMUser*, which allows to :

  * view
  * backup
  * config CDROM
  * VM console
  * VM power management

Maybe you should create your own role with restricted privileges.

Then you can add your VMs to a pool (for example `fence`) and finaly give permissions on
the path `/pool/fence/` to the user. Note: On promox, a user is designated by his full path `user@realm` (here `hauser@pve`).

So in this example :

Virtual machines are in the pool `fence` and the user `hauser@pve` has the role *PVEVMUser* for the path
`/pool/fence/`.

You must ensure all your VMs can reach Proxmox nodes, you can try with:

`fence_pve --vmtype lxc  --ip=192.168.10.1 --username=hauser@pve --password=hauser --plug 111 --action=status`

Where:

  * vmtype: is virtual machine type. lxc or qemu (default).
  * ip: hypervisor ip address
  * username: full username
  * password: user's password
  * plug: container's id
  * action: show container's status

If the container is running you should obtain: `Status: ON`.

You can list all containers available with list action:

```
fence_pve --vmtype lxc  -a 192.168.10.1 -l hauser@pve -p hauser --plug 111   -o list
109,paf-1
111,paf-3
110,paf-2
```

Other actions are available, such as: on, off, reboot (default).

Once your have checked all your VMs can reach Proxmox host, you must check on, off and reboot actions.
Then you can add fencing resources to your cluster. For example with pcs :

```
pcs stonith create fence_vm_paf1 fence_pve pcmk_host_list="paf-1" pcmk_host_check="static-list" \
  ipaddr="192.168.10.1" node_name="sd-89884" login="hauser@pve" passwd="hauser" port="109" \
  power_wait="10" vmtype="lxc"
pcs stonith create fence_vm_paf2 fence_pve pcmk_host_list="paf-2" pcmk_host_check="static-list" \
  ipaddr="192.168.10.1" node_name="sd-89884" login="hauser@pve" passwd="hauser" port="110" \
  power_wait="10" vmtype="lxc"
pcs stonith create fence_vm_paf3 fence_pve pcmk_host_list="paf-3" pcmk_host_check="static-list" \
  ipaddr="192.168.10.1" node_name="sd-89884" login="hauser@pve" passwd="hauser" port="111" \
  power_wait="10" vmtype="lxc"
```

Notice the `node_name` parameter corresponding to proxmox host and `power_wait`. Without this last
parameter the fencing agent do not wait between off/on for reboot action. So the container do not start
because proxmox do not had time to shutdown container.

## Resource fencing using SNMP

This fencing method allows you to shutdown an ethernet port on a manageable
switch using the SNMP protocol. This is useful to cut off all accesses to the
world to your "node-to-fence" or its iSCSI access to data.

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

__Warning__: if you are fencing a node cutting off its network accessed, take
great care when you unfence it.
While fenced, the node might get angry and try to fence other node when coming
back. You better want some quorum setup to keep it under control, or manually
switching off pacemaker before unfencing it.

## Using a watchdog device

Watchdog devices are hardware able to reset servers on various conditions. The
basic one is to reset the server on external demand, allowing the node to
fence itself if needed (eg. failing to demote/stop a primary).

Watchdogs are often initialized to start timer and reset the server if the timer
elapses. An external program is then supposed to reset this timer before it
times out to keep the system alive.

A watchdog can act as a fencing device but does not cover as many failure
scenarios as external fencing devices (a network split in a two node cluster for
instance). They can nevertheless be useful as last resort in environment where
fencing is not possible and Pacemaker then accepts to start the resources. 

Setting up a watchdog with Pacemaker requires some system setup that differs
among Linux distributions. For examples, see:

* chapter in [Setting up a watchdog]({{ site.baseurl }}/CentOS-7-admin-cookbook.html#setting-up-a-watchdog)
  in the Administration cookbook with CentOS 7
* WIP for debian 8
