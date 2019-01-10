#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

PGVER="$1"
HAPASS="$2"
MASTER_IP="$3"
SSH_LOGIN="$4"
VM_PREFIX="$5"
HOST_IP="$6"
PGDATA="$7"
shift 7
NODES=( "$@" )

pcs cluster auth -u hacluster -p "${HAPASS}" "${NODES[@]}"

pcs cluster setup --name cluster_pgsql --wait --force "${NODES[@]}"

pcs stonith sbd enable

pcs cluster start --all --wait

pcs cluster cib cluster1.xml

pcs -f cluster1.xml resource defaults migration-threshold=5
pcs -f cluster1.xml resource defaults resource-stickiness=10
pcs -f cluster1.xml property set stonith-watchdog-timeout=10s

for VM in "${NODES[@]}"; do
    FENCE_ID="fence_vm_${VM}"
    VM_PORT="${VM_PREFIX}_${VM}"
    pcs -f cluster1.xml stonith create "${FENCE_ID}" fence_virsh    \
        pcmk_host_check=static-list "pcmk_host_list=${VM}" \
        "port=${VM_PORT}" "ipaddr=${HOST_IP}" "login=${SSH_LOGIN}"  \
        "identity_file=/root/.ssh/id_rsa"
    pcs -f cluster1.xml constraint location "fence_vm_${VM}" \
        avoids "${VM}=INFINITY"
done

pcs -f cluster1.xml resource create pgsqld "ocf:heartbeat:pgsqlms" \
    "bindir=/usr/pgsql-${PGVER}/bin" "pgdata=${PGDATA}"            \
    op start timeout=60s                                           \
    op stop timeout=60s                                            \
    op promote timeout=30s                                         \
    op demote timeout=120s                                         \
    op monitor interval=15s timeout=10s role=Master                \
    op monitor interval=16s timeout=10s role=Slave                 \
    op notify timeout=60s

pcs -f cluster1.xml resource master pgsql-ha pgsqld notify=true

pcs -f cluster1.xml resource create pgsql-master-ip           \
    "ocf:heartbeat:IPaddr2" "ip=${MASTER_IP}" cidr_netmask=24 \
    op monitor interval=10s

pcs -f cluster1.xml constraint colocation add pgsql-master-ip with master pgsql-ha INFINITY
pcs -f cluster1.xml constraint order promote pgsql-ha "then" start pgsql-master-ip symmetrical=false
pcs -f cluster1.xml constraint order demote pgsql-ha "then" stop pgsql-master-ip symmetrical=false

pcs cluster cib-push scope=configuration cluster1.xml --wait

pcs config

crm_mon -nr1
