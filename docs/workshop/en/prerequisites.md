# Prerequisites

Before attending to this workshop, attendies should have preprared their
computer with the following:

* libvirtd
* virt-manager
* 3 VM running CentOS 7
* SSH authentication between the VM -> user@hypervisor
* the VM should be able to ping each other

## Préparation of the MV

* Exchange SSH keys between the root users on the VM and the hypervisor user:
  
  ~~~
  ssh-keygen
  ssh-copy-id <user>@<ip hyperviseur>
  ~~~

* The VM should be able to communicate between eachother using their node names,
  e.g.:
  
  ~~~
  cat >> /etc/hosts <<EOF
  192.168.122.101 hanode1
  192.168.122.102 hanode2
  192.168.122.103 hanode3
  192.168.122.110 ha-vip
  EOF
  ~~~

## Firewall

* Authorize postgresql and the high availability services:
  
  ~~~
  firewall-cmd --permanent --add-service=high-availability
  firewall-cmd --permanent --add-service=postgresql
  firewall-cmd --reload
  ~~~

## Temporary directory

* On each node create a temporary directory: `/tmp/sub`

  ~~~
  mkdir /tmp/sub
  ~~~
