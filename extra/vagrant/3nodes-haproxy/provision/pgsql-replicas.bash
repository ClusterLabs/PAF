#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

PGVER="$1"
NODENAME="$2"
PGDATA="$3"

CUSTOMDIR="${PGDATA}/conf.d"

# cleanup
systemctl --quiet --now disable "postgresql-${PGVER}"
rm -rf "${PGDATA}"

# build standby
"/usr/pgsql-${PGVER}/bin/pg_basebackup" -h 127.0.0.1 -U postgres -D "${PGDATA}" -X stream

# set pg_hba
cat<<EOC > "${PGDATA}/pg_hba.conf"
local all         all                      trust
host  all         all      0.0.0.0/0       trust

local replication all                 reject
host  replication all $NODENAME       reject
host  replication all 127.0.0.1/32    reject
host  replication all ::1/128         reject
# allow any standby connection
host  replication all 0.0.0.0/0       trust
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
