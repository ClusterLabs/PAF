# How to bootstrap a cluster using vagrant

This `Vagrantfile` is bootstrapping a fresh cluster with:

* servers `srv1`, `srv2` and `srv3` hosting a pgsql cluster with streaming replication
* pgsql primary is on `srv1` and the two standby are on `srv2` and `srv3`
* server `log-sink` where all logs from `srv1`, `srv2` and `srv3` are collected under `/var/log/<server>`
* pacemaker stack is setup on `srv1`, `srv2` and `srv3`
* fencing using fence_virsh
* watchdog enabled

Note that NTP is enabled by default (using chrony) in the vagrant box used (`centos/7`).
No need to set it up ourselves.

## Prerequisites:


You need `vagrant` and `vagrant-libvirt`. Everything is tested with versions 2.0.2 and
0.0.40. Please, report your versions if it works with inferior ones.

~~~
apt install make vagrant vagrant-libvirt libvirt-clients # for Debian-like
yum install make vagrant vagrant-libvirt libvirt-client # for RH-like
dnf install make vagrant vagrant-libvirt libvirt-client # for recent RH-like
systemctl enable --now libvirtd
~~~

Alternatively, you might be able to install vagrant-libvirt only for your current user
using (depending on the system, this might not work):

~~~
vagrant plugin install vagrant-libvirt
~~~

Pacemaker must be able to ssh to the libvirt host with no password using a user able
to `virsh destroy $other_vm`. Here are the steps:

* copy `<PAF>/test/ssh/id_rsa.pub` inside `user@host:~/.ssh/authorized_keys`
* edit `ssh_login` in the `vagrant.yml` configuration file
* user might need to be in group `libvirt`
* user might need to add `uri_default='qemu:///system'` in its
  file `~<user>/.config/libvirt/libvirt.conf`
* make sure sshd is started on the host

Here is a setup example:

~~~
####  Replace "myuser" with your usual user  ####
root$ systemctl start sshd
root$ export MYUSER=myuser
root$ usermod -a -G libvirt "$MYUSER"
root$ su - $MYUSER
myuser$ mkdir -p "${HOME}/.config/libvirt"
myuser$ echo "uri_default='qemu:///system'" > "${HOME}/.config/libvirt/libvirt.conf"
myuser$ git clone https://github.com/ClusterLabs/PAF.git
myuser$ cd PAF/test
myuser$ cat "ssh/id_rsa.pub" >> "${HOME}/.ssh/authorized_keys"
myuser$ echo "ssh_login: \"$USER\"" >> vagrant.yml
~~~

## Creating the cluster

To create the cluster, run:

~~~
cd PAF/test
make all
~~~

After some minutes and tons of log messages, you can connect to your servers using eg.:

~~~
vagrant ssh srv1
vagrant ssh log-sink
~~~

## Destroying the cluster

To destroy your cluster, run:

~~~
vagrant destroy -f
~~~


## Customization

You can edit file `vagrant.yml`:

~~~
cp vagrant.yml-dist vagrant.yml
$EDITOR vagrant.yml
make clean
make all
~~~

## Cluster Test Suite

You can install the Cluster Test Suite from the Pacemaker project using:

~~~
vagrant up --provision-with=cts
~~~

Then, you'll be able to start the exerciser from the log-sink server using eg.:

~~~
vagrant ssh -c "sudo pcs cluster stop --all"
vagrant ssh log-sink
sudo -i
cd /usr/share/pacemaker/tests/cts
./CTSlab.py --nodes "srv1 srv2 srv3" --outputfile ~/cts.log --once
~~~

You can select the test you want to run with:

~~~
./CTSlab.py --nodes "srv1 srv2 srv3" --list-tests
./CTSlab.py --nodes "srv1 srv2 srv3" --outputfile ~/cts.log --choose <$NAME> 1
~~~

Where `<$NAME>` is the name of the test you want to run.

You can exercise the cluster randomly and repetitively with:

~~~
./CTSlab.py --nodes "srv1 srv2 srv3" --outputfile ~/cts.log <$NTESTS>
~~~

## Tips

Find all existing VM created by vagrant on your system:

~~~
vagrant global-status
~~~

Shutdown all VM:

~~~
vagrant ssh -c "sudo pcs resource disable pgsql-ha --wait"
vagrant halt
~~~

Restart cluster:

~~~
vagrant up
vagrant ssh -c "sudo pcs cluster start --all"
vagrant ssh -c "sudo pcs resource enable pgsql-ha --wait"
~~~
