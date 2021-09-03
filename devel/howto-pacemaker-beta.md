# How to test with latest Pacemaker source code

The has been tested on Centos 8 Stream.

First, install some dependencies:

~~~bash
yum install --enablerepo=ha --enablerepo=powertools make git      \
    corosync corosynclib corosynclib-devel python3 libqb-devel    \
    bzip2-devel libxslt-devel libxml2-devel glib2-devel pkgconfig \
    libuuid-devel libtool-ltdl-devel libtool autoconf automake    \
    docbook-style-xsl gnutls-devel help2man ncurses-devel         \
    pam-devel pkgconfig 'pkgconfig(dbus-1)' python3-devel         \
    rpmdevtools rpmlint perl-TimeDate psmisc resource-agents
~~~

Get the source code and checkout the required tag/commit:

~~~bash
git clone https://github.com/ClusterLabs/pacemaker.git
cd pacemaker
git checkout Pacemaker-2.1.1-rc3
~~~

Build the code and RPM:

~~~bash
./autogen.sh
./configure
make rpm
~~~

Install pacemaker:

~~~bash
cd rpm/RPMS
yum install ./x86_64/pacemaker-2.1.1-0.1.rc3.el8.x86_64.rpm              \
            ./x86_64/pacemaker-cli-2.1.1-0.1.rc3.el8.x86_64.rpm          \
            ./x86_64/pacemaker-libs-2.1.1-0.1.rc3.el8.x86_64.rpm         \
            ./x86_64/pacemaker-cluster-libs-2.1.1-0.1.rc3.el8.x86_64.rpm \
            ./noarch/pacemaker-schemas-2.1.1-0.1.rc3.el8.noarch.rpm
~~~

