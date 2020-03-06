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

# build standby
"/usr/pgsql-${PGVER}/bin/pg_basebackup" -h "${MASTER_IP}" -U postgres -D "${PGDATA}" -X stream

# set pg_hba
cat<<EOC > "${PGDATA}/pg_hba.conf"
local all         all                      trust
host  all         all      0.0.0.0/0       trust

# forbid self-replication
host  replication postgres ${MASTER_IP}/32 reject
host  replication postgres ${NODENAME}     reject

# allow any standby connection
host  replication postgres 0.0.0.0/0       trust
EOC
cp "${PGDATA}/pg_hba.conf"        "${PGDATA}/.."

if [ "${PGVER%%.*}" -lt 12 ]; then
    # recovery.conf setup
    cat<<-EOC > "${CUSTOMDIR}/recovery.conf.pcmk"
	standby_mode = on
	primary_conninfo = 'host=${MASTER_IP} application_name=${NODENAME}'
	recovery_target_timeline = 'latest'
	EOC
    cp "${CUSTOMDIR}/recovery.conf.pcmk" "${PGDATA}/recovery.conf"
else
    cat <<-EOC > "${CUSTOMDIR}/repli.conf"
	primary_conninfo = 'host=${MASTER_IP} application_name=${NODENAME}'
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
