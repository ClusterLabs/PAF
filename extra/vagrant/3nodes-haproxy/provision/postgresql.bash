#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

PGVER="$1"
NODENAME="$2"
PGDATA="$3"

# shellcheck disable=SC1091
source "/etc/os-release"
OS_VER="$VERSION_ID"
YUM_INSTALL="yum install --nogpgcheck --quiet -y -e 0"

if ! rpm --quiet -q "pgdg-redhat-repo"; then
    if [ "${OS_VER:0:2}" = "8." ]; then
        $YUM_INSTALL "https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm"
    else
        $YUM_INSTALL "https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm"
    fi
fi

# disable postgresql upstream module conflicting with pgdg packages in RHEL8
if [ "${OS_VER:0:2}" = "8." ]; then
    yum -qy module disable postgresql
fi

PACKAGES=(
    "postgresql${PGVER}"
    "postgresql${PGVER}-server"
    "postgresql${PGVER}-contrib"
)

$YUM_INSTALL "${PACKAGES[@]}"

# PostgreSQL state
cat<<'EOF' > /etc/systemd/system/pgsql-state@.service
[Unit]
Description=Local PostgreSQL state

[Service]
User=postgres
Group=postgres
ExecStart=/usr/pgsql-12/bin/psql -d postgres -U postgres -p 5434 -Atc "select CASE pg_is_in_recovery() WHEN true THEN 'standby' ELSE 'production' END"
StandardOutput=socket
EOF

cat<<'EOF' > /etc/systemd/system/pgsql-state.socket
[Unit]
Description=Local PostgreSQL state

[Socket]
ListenStream=5431
Accept=yes

[Install]
WantedBy=sockets.target
EOF

systemctl --quiet --now enable pgsql-state.socket

# firewall setup
firewall-cmd --quiet --permanent --service=postgresql --add-port="5433/tcp"
firewall-cmd --quiet --permanent --service=postgresql --add-port="5434/tcp"
firewall-cmd --quiet --permanent --remove-service=postgresql
firewall-cmd --quiet --permanent --add-service=postgresql
if ! firewall-cmd --get-services|grep -q pgsql-state; then
    firewall-cmd --quiet --permanent --new-service="pgsql-state"
    firewall-cmd --quiet --permanent --service="pgsql-state" --set-description="Local PostgreSQL state"
    firewall-cmd --quiet --permanent --service="pgsql-state" --add-port="5431/tcp"
fi
firewall-cmd --quiet --permanent --add-service="pgsql-state"
firewall-cmd --quiet --reload

if [ "$(hostname -s)" != "$NODENAME" ]; then
    exit 0
fi

# Build the primary
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

local replication all                 reject
host  replication all $NODENAME       reject
host  replication all 127.0.0.1/32    reject
host  replication all ::1/128         reject
# allow any standby connection
host  replication postgres 0.0.0.0/0       trust
EOC

# postgresql.conf setup
mkdir -p "$CUSTOMDIR"
echo "include_dir = 'conf.d'" >> "${PGDATA}/postgresql.conf"

cat <<EOC > "${CUSTOMDIR}/cluster_name.conf"
cluster_name = 'pgsql-$NODENAME'
EOC

cat <<'EOC' > "${CUSTOMDIR}/custom.conf"
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
log_line_prefix = '%m [%p] host=%h '
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
    # no need to add recovery_target_timeline as its default is 'latest' since v12
fi

# backing up files
cp "${PGDATA}/pg_hba.conf"        "${PGDATA}/.."
cp "${PGDATA}/postgresql.conf"    "${PGDATA}/.."
cp "${CUSTOMDIR}"/*               "${PGDATA}/.."

chown -R postgres:postgres "$PGDATA"

# restart master pgsql
systemctl --quiet start "postgresql-${PGVER}"
