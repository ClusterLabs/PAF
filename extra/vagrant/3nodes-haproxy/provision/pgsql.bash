#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

declare -r NODENAME="$1"
declare -r PGVER="$2"
declare -r PGDATA="$3"

declare -r PRIM_NODE="$4"

declare -r CUSTOMDIR="${PGDATA}/conf.d"

# cleanup
systemctl --quiet --now disable "postgresql-${PGVER}"
rm -rf "${PGDATA}"

if [ "$NODENAME" == "$PRIM_NODE" ]; then
    # init instance
    "/usr/pgsql-${PGVER}/bin/postgresql-${PGVER}-setup" initdb

    # pg_hba setup
    cat<<-EOC > "${PGDATA}/pg_hba.conf"
	local all         all                      trust
	host  all         all      0.0.0.0/0       trust

	# forbid self-replication
	local replication all                      reject
	host  replication all ${NODENAME}          reject
	host  replication all 127.0.0.1/32         reject
	host  replication all ::1/128              reject


	# allow any standby connection
	host  replication postgres 0.0.0.0/0       trust
	EOC

    # postgresql.conf setup
    mkdir -p "$CUSTOMDIR"
    echo "include_dir = 'conf.d'" >> "${PGDATA}/postgresql.conf"

    cat <<-EOC > "${CUSTOMDIR}/cluster_name.conf"
	cluster_name = 'pgsql-$NODENAME'
	EOC

    cat <<-'EOC' > "${CUSTOMDIR}/custom.conf"
	listen_addresses = '*'
	port = 5434
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
		primary_conninfo = 'host=127.0.0.1 application_name=${NODENAME}'
		recovery_target_timeline = 'latest'
		EOC
    else
		cat <<-EOC > "${CUSTOMDIR}/repli.conf"
		primary_conninfo = 'host=127.0.0.1 application_name=${NODENAME}'
		EOC

		# standby_mode disappear in v12
		# no need to add recovery_target_timeline as its default is 'latest'
		# since v12
    fi

    # backing up files
    cp "${PGDATA}/pg_hba.conf"        "${PGDATA}/.."
    cp "${PGDATA}/postgresql.conf"    "${PGDATA}/.."
    cp "${CUSTOMDIR}"/*               "${PGDATA}/.."

    chown -R postgres:postgres "$PGDATA"

    # restart master pgsql
    systemctl --quiet start "postgresql-${PGVER}"

    exit
fi

# building standby

# wait for the primary to listen
while ! "/usr/pgsql-${PGVER}/bin/pg_isready" -qh "127.0.0.1"; do sleep 1 ; done


# build standby
"/usr/pgsql-${PGVER}/bin/pg_basebackup" -h 127.0.0.1 -U postgres \
	-D "${PGDATA}" -X stream

# set pg_hba
cat<<EOC > "${PGDATA}/pg_hba.conf"
local all         all                      trust
host  all         all      0.0.0.0/0       trust

# forbid self-replication
local replication all                      reject
host  replication all ${NODENAME}          reject
host  replication all 127.0.0.1/32         reject
host  replication all ::1/128              reject


# allow any standby connection
host  replication postgres 0.0.0.0/0       trust
EOC

cat <<EOC > "${CUSTOMDIR}/cluster_name.conf"
cluster_name = 'pgsql-$NODENAME'
EOC

if [ "${PGVER%%.*}" -lt 12 ]; then
    # recovery.conf setup
    cat<<-EOC > "${CUSTOMDIR}/recovery.conf.pcmk"
	standby_mode = on
	primary_conninfo = 'host=127.0.0.1 application_name=${NODENAME}'
	recovery_target_timeline = 'latest'
	EOC

    cp "${CUSTOMDIR}/recovery.conf.pcmk" "${PGDATA}/recovery.conf"
else
    cat <<-EOC > "${CUSTOMDIR}/repli.conf"
	primary_conninfo = 'host=127.0.0.1 application_name=${NODENAME}'
	EOC

    # standby_mode disappear in v12
    # no need to add recovery_target_timeline as its default is 'latest' since v12
    touch "${PGDATA}/standby.signal"
fi

# backing up files
cp "${PGDATA}/pg_hba.conf"        "${PGDATA}/.."
cp "${PGDATA}/postgresql.conf"    "${PGDATA}/.."
cp "${CUSTOMDIR}"/*               "${PGDATA}/.."

chown -R "postgres:postgres" "${PGDATA}/.."

# start
systemctl --quiet start "postgresql-${PGVER}"
