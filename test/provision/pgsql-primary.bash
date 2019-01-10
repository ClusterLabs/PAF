#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

PGVER="$1"
PGDATA="$2"
MASTER_IP="$3"
NODENAME="$4"

systemctl stop "postgresql-${PGVER}"
systemctl disable "postgresql-${PGVER}"
rm -rf "${PGDATA}"

# init instance
"/usr/pgsql-${PGVER}/bin/postgresql-${PGVER}-setup" initdb

# pg_hba setup
cat<<EOC > "${PGDATA}/pg_hba.conf"
local all         all                      trust
host  all         all      0.0.0.0/0       trust

# forbid self-replication
host  replication postgres ${MASTER_IP}/32 reject
host  replication postgres ${NODENAME}     reject

# allow any standby connection
host  replication postgres 0.0.0.0/0       trust
EOC

systemctl start "postgresql-${PGVER}"

# postgresql.conf setup
cat <<EOS | "/usr/pgsql-${PGVER}/bin/psql" -U postgres
ALTER SYSTEM SET "listen_addresses" TO '*';
ALTER SYSTEM SET "wal_level" TO 'replica';
ALTER SYSTEM SET "max_wal_senders" TO '10';
ALTER SYSTEM SET "hot_standby" TO 'on';
ALTER SYSTEM SET "hot_standby_feedback" TO 'on';
ALTER SYSTEM SET "wal_keep_segments" TO '256';
ALTER SYSTEM SET "log_destination" TO 'syslog,stderr';
ALTER SYSTEM SET "log_checkpoints" TO 'on';
ALTER SYSTEM SET "log_min_duration_statement" TO '0';
ALTER SYSTEM SET "log_autovacuum_min_duration" TO '0';
ALTER SYSTEM SET "log_replication_commands" TO 'on';
EOS

# recovery.conf setup
cat<<EOC > "${PGDATA}/recovery.conf.pcmk"
standby_mode = on
primary_conninfo = 'host=${MASTER_IP} application_name=${NODENAME}'
recovery_target_timeline = 'latest'
EOC

# backing up files
cp "${PGDATA}/pg_hba.conf"        "${PGDATA}/.."
cp "${PGDATA}/postgresql.conf"    "${PGDATA}/.."
cp "${PGDATA}/recovery.conf.pcmk" "${PGDATA}/.."

# create master ip
DEV=$(ip route show to "${MASTER_IP}/24"|grep -Eo 'dev \w+')
ip addr add "${MASTER_IP}/24" dev "${DEV/dev }"

# restart master pgsql
systemctl restart "postgresql-${PGVER}"
