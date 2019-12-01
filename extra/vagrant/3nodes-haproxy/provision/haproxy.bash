#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

YUM_INSTALL="yum install --nogpgcheck --quiet -y -e 0"

$YUM_INSTALL haproxy

systemctl --quiet --now disable haproxy

cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg-dist
cat <<'EOF' > /etc/haproxy/haproxy.cfg
global
    log         127.0.0.1:514 local2
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon

    stats socket /var/lib/haproxy/stats

defaults
    mode            tcp
    log             global
    option          tcplog
    retries         3
    timeout connect 10s
    timeout client  10m
    timeout server  10m
    timeout check   1s
    maxconn         300

listen stats
    mode http
    bind *:7000
    stats enable
    stats uri /
    timeout connect 15s
    timeout client  15s
    timeout server  15s

listen prd
    bind           *:5432
    option         tcp-check
    tcp-check      connect port 5431
    tcp-check      expect string production
    default-server inter 2s fastinter 1s rise 2 fall 1 on-marked-down shutdown-sessions
    server         srv1 srv1:5434 check
    server         srv2 srv2:5434 check
    server         srv3 srv3:5434 check

listen stb
    bind           *:5433
    balance        leastconn
    option         tcp-check
    tcp-check      connect port 5431
    tcp-check      expect string standby
    default-server inter 2s fastinter 1s rise 2 fall 1 on-marked-down shutdown-sessions
    server         srv1 srv1:5434 check
    server         srv2 srv2:5434 check
    server         srv3 srv3:5434 check
EOF

setsebool -P haproxy_connect_any=1

systemctl --quiet --now enable haproxy

if ! firewall-cmd --get-services|grep -q haproxy-stats; then
    firewall-cmd --quiet --permanent --new-service="haproxy-stats"
    firewall-cmd --quiet --permanent --service="haproxy-stats" --set-description="HAProxy statistics"
    firewall-cmd --quiet --permanent --service="haproxy-stats" --add-port="7000/tcp"
fi
firewall-cmd --quiet --permanent --add-service="haproxy-stats"
firewall-cmd --quiet --reload
