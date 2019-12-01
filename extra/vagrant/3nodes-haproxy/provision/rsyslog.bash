#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

LOG_SINK="$1"

if [ "$(hostname -s)" == "$LOG_SINK" ]; then
    # setup log sink
    cat <<-'EOF' > /etc/rsyslog.d/log_sink.conf
	$ModLoad imtcp 
	$InputTCPServerRun 514

	$template RemoteLogsMerged,"/var/log/%HOSTNAME%/messages.log"
	*.* ?RemoteLogsMerged

	$template RemoteLogs,"/var/log/%HOSTNAME%/%PROGRAMNAME%.log"
	*.* ?RemoteLogs
	#& ~
	EOF

    if ! firewall-cmd --get-services|grep -q rsyslog-tcp; then
        firewall-cmd --quiet --permanent --new-service="rsyslog-tcp"
        firewall-cmd --quiet --permanent --service="rsyslog-tcp" --set-description="RSyslog TCP port"
        firewall-cmd --quiet --permanent --service="rsyslog-tcp" --add-port="514/tcp"
    fi
    firewall-cmd --quiet --permanent --add-service="rsyslog-tcp"
    firewall-cmd --quiet --reload

    semanage port -m -t syslogd_port_t -p tcp 514
else
    # send logs to log-sinks
    cat <<-'EOF' >/etc/rsyslog.d/20-fwd_log_sink.conf
	*.* action(type="omfwd"
	queue.type="LinkedList"
	queue.filename="log_sink_fwd"
	action.resumeRetryCount="-1"
	queue.saveonshutdown="on"
	target="log-sink" Port="514" Protocol="tcp")
	EOF

    # listen for haproxy logs locally
	cat <<-'EOF' >/etc/rsyslog.d/10-haproxy.conf
	$ModLoad imudp
	$UDPServerAddress 127.0.0.1
	$UDPServerRun 514
	EOF
fi

systemctl --quiet restart rsyslog
