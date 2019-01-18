#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

PGVER="$1"
PGDATA="$2"
MASTER_IP="$3"
NODENAME="$4"

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

# recovery.conf
cat<<EOC > "${PGDATA}/recovery.conf.pcmk"
standby_mode = on
primary_conninfo = 'host=${MASTER_IP} application_name=${NODENAME}'
recovery_target_timeline = 'latest'
EOC

# backup conf files
cp "${PGDATA}/pg_hba.conf"        "${PGDATA}/.."
cp "${PGDATA}/recovery.conf.pcmk" "${PGDATA}/.."
cp "${PGDATA}/recovery.conf.pcmk" "${PGDATA}/recovery.conf"

chown -R "postgres:postgres" "${PGDATA}/.."

# start
systemctl --quiet start "postgresql-${PGVER}"
