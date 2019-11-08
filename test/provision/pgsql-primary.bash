#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

PGVER="$1"
PGDATA="$2"
MASTER_IP="$3"
NODENAME="$4"

CUSTOMDIR="${PGDATA}/conf.d"

# cleanup
systemctl --quiet --now disable "postgresql-${PGVER}"
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

# postgresql.conf setup
mkdir -p "$CUSTOMDIR"
echo "include_dir = 'conf.d'" >> "${PGDATA}/postgresql.conf"

cat <<'EOC' > "${CUSTOMDIR}/custom.conf"
listen_addresses = '*'
wal_level = replica
max_wal_senders = 10
hot_standby = on
hot_standby_feedback = on
wal_keep_segments = 256
log_destination = 'syslog,stderr'
log_checkpoints = on
log_min_duration_statement = 0
log_autovacuum_min_duration = 0
log_replication_commands = on
EOC

if [ "${PGVER%%.*}" -lt 12 ]; then
    # recovery.conf setup
    cat<<-EOC > "${CUSTOMDIR}/recovery.conf.pcmk"
	standby_mode = on
	primary_conninfo = 'host=${MASTER_IP} application_name=${NODENAME}'
	recovery_target_timeline = 'latest'
	EOC
else
    cat <<-EOC > "${CUSTOMDIR}/repli.conf"
	primary_conninfo = 'host=${MASTER_IP} application_name=${NODENAME}'
	EOC

    # standby_mode disappear in v12
    # no need to add recovery_target_timeline as its default is 'latest' since v12
fi

# backing up files
cp "${PGDATA}/pg_hba.conf"        "${PGDATA}/.."
cp "${PGDATA}/postgresql.conf"    "${PGDATA}/.."
cp "${CUSTOMDIR}"/*               "${PGDATA}/.."

chown -R postgres:postgres "$PGDATA"

# create master ip
ip -o addr show to "${MASTER_IP}" | if ! grep -q "${MASTER_IP}"
then
    DEV=$(ip route show to "${MASTER_IP}/24"|grep -Eo 'dev \w+')
    ip addr add "${MASTER_IP}/24" dev "${DEV/dev }"
fi

# restart master pgsql
systemctl --quiet start "postgresql-${PGVER}"
