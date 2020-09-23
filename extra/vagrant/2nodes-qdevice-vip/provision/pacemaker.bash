#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

declare PCMK_VER
declare -a PGSQLD_RSC_OPTS
declare -r PGVER="$1"
declare -r HAPASS="$2"
declare -r PRIM_IP="$3"
declare -r PGDATA="$4"
declare -r QD_NODE="$5"


shift 5
declare -r -a NODES=( "$@" )

declare -r CUSTOMDIR="${PGDATA}/conf.d"

# extract pacemaker major version
PCMK_VER=$(yum info --quiet pacemaker|grep ^Version)
PCMK_VER="${PCMK_VER#*: }" # extract x.y.z
PCMK_VER="${PCMK_VER:0:1}" # extract x

if [ "$PCMK_VER" -ge 2 ]; then
    # if pacemaker version is 2.x, we suppose pcs support it (pcs >= 0.10)
    # from pcs 0.10, pcs host auth must be exec'ed on each node
    pcs host auth -u hacluster -p "${HAPASS}" "${NODES[@]}" "$QD_NODE"
else
    # this could be run on one node, but it doesn't hurt if it runs everywhere,
    # so we keep this piece of code with the one dedicated to pacemaker 2.x
    pcs cluster auth -u hacluster -p "${HAPASS}" "${NODES[@]}" "$QD_NODE"
fi

if [ "$(hostname -s)" != "${NODES[0]}" ]; then
    exit 0
fi

# WARNING:
# Starting from here, everything is executed on first node only!

if [ "$PCMK_VER" -ge 2 ]; then
    pcs cluster setup cluster_pgsql --force "${NODES[@]}"
else
    pcs cluster setup --name cluster_pgsql --wait --force "${NODES[@]}"
fi

pcs stonith sbd enable

pcs quorum device add model net host=qd algorithm=ffsplit

pcs cluster start --all --wait

pcs cluster cib cluster1.xml

pcs -f cluster1.xml resource defaults migration-threshold=5
pcs -f cluster1.xml resource defaults resource-stickiness=10
pcs -f cluster1.xml property set stonith-watchdog-timeout=10s

PGSQLD_RSC_OPTS=(
    "ocf:heartbeat:pgsqlms"
    "bindir=/usr/pgsql-${PGVER}/bin"
    "pgdata=${PGDATA}"
    "recovery_template=${CUSTOMDIR}/recovery.conf.pcmk"
    "op" "start"   "timeout=60s"
    "op" "stop"    "timeout=60s"
    "op" "promote" "timeout=30s"
    "op" "demote"  "timeout=120s"
    "op" "monitor" "interval=15s" "timeout=10s" "role=Master"
    "op" "monitor" "interval=16s" "timeout=10s" "role=Slave"
    "op" "notify"  "timeout=60s"
)

# NB: pcs 0.10.2 doesn't support to set the id of the clone XML node
# the id is built from the rsc id to clone using "<rsc-id>-clone"
# As a matter of cohesion and code simplicity, we use the same
# convention to create the master resource with pcs 0.9.x for
# Pacemaker 1.1
if [ "$PCMK_VER" -ge 2 ]; then
    PGSQLD_RSC_OPTS+=( "promotable" "notify=true" )
fi

pcs -f cluster1.xml resource create pgsqld "${PGSQLD_RSC_OPTS[@]}"

if [ "$PCMK_VER" -eq 1 ]; then
    pcs -f cluster1.xml resource master pgsqld-clone pgsqld notify=true
fi

pcs -f cluster1.xml resource create pgsql-pri-ip         \
    "ocf:heartbeat:IPaddr2" "ip=${PRIM_IP}" cidr_netmask=24 \
    op monitor interval=10s

pcs -f cluster1.xml constraint colocation \
    add pgsql-pri-ip with master pgsqld-clone INFINITY
pcs -f cluster1.xml constraint order      \
    promote pgsqld-clone "then" start pgsql-pri-ip symmetrical=false
pcs -f cluster1.xml constraint order      \
    demote pgsqld-clone  "then" stop  pgsql-pri-ip symmetrical=false

pcs cluster cib-push scope=configuration cluster1.xml --wait

crm_mon -Dn1
