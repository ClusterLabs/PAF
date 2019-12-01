#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# install packages

PACKAGES=(
    pacemaker-cts patch
)

yum install --nogpgcheck --quiet -y -e 0 "${PACKAGES[@]}"

# do not drop any log messages from rsyslog
cat <<'EOF'>/etc/rsyslog.d/rateLimit.conf
$imjournalRatelimitInterval 0
$imjournalRatelimitBurst 0
EOF

systemctl --quiet restart rsyslog

# make journald logs persistent
mkdir -p /var/log/journal

# do not drop any log messages from journald
mkdir -p /etc/systemd/journald.conf.d
cat <<'EOF'>/etc/systemd/journald.conf.d/rateLimit.conf
RateLimitInterval=0
RateLimitBurst=0
EOF

systemctl --quiet restart systemd-journald


# shellcheck disable=SC1091
source "/etc/os-release"
OS_VER="$VERSION_ID"
if [ "${OS_VER:0:2}" != "7." ]; then exit; fi

# fix bug in the log watcher for EL7
cat <<'EOF' | patch /usr/lib64/python2.7/site-packages/cts/watcher.py
*** /tmp/watcher.py.orig	2019-02-07 16:25:32.836265277 +0100
--- /tmp/watcher.py	2019-02-07 16:27:03.296926885 +0100
***************
*** 124,130 ****
          self.offset = "EOF"
  
          if host == None:
!             host = "localhost"
  
      def __str__(self):
          if self.host:
--- 124,130 ----
          self.offset = "EOF"
  
          if host == None:
!             self.host = "localhost"
  
      def __str__(self):
          if self.host:
***************
*** 155,179 ****
  class FileObj(SearchObj):
      def __init__(self, filename, host=None, name=None):
          global has_log_watcher
!         SearchObj.__init__(self, filename, host, name)
! 
!         if host is not None:
!             if not host in has_log_watcher:
  
!                 global log_watcher
!                 global log_watcher_bin
  
!                 self.debug("Installing %s on %s" % (log_watcher_file, host))
  
!                 os.system("cat << END >> %s\n%s\nEND" %(log_watcher_file, log_watcher))
!                 os.system("chmod 755 %s" %(log_watcher_file))
  
!                 self.rsh.cp(log_watcher_file, "root@%s:%s" % (host, log_watcher_bin))
!                 has_log_watcher[host] = 1
  
!                 os.system("rm -f %s" %(log_watcher_file))
  
!             self.harvest()
  
      def async_complete(self, pid, returncode, outLines, errLines):
          for line in outLines:
--- 155,176 ----
  class FileObj(SearchObj):
      def __init__(self, filename, host=None, name=None):
          global has_log_watcher
!         global log_watcher
!         global log_watcher_bin
  
!         SearchObj.__init__(self, filename, host, name)
  
!         self.debug("Installing %s on %s" % (log_watcher_file, self.host))
  
!         os.system("cat << END >> %s\n%s\nEND" %(log_watcher_file, log_watcher))
!         os.system("chmod 755 %s" %(log_watcher_file))
  
!         self.rsh.cp(log_watcher_file, "root@%s:%s" % (self.host, log_watcher_bin))
!         has_log_watcher[self.host] = 1
  
!         os.system("rm -f %s" %(log_watcher_file))
  
!         self.harvest()
  
      def async_complete(self, pid, returncode, outLines, errLines):
          for line in outLines:

EOF

