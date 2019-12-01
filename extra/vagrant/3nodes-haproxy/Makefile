export VAGRANT_BOX_UPDATE_CHECK_DISABLE=1
export VAGRANT_CHECKPOINT_DISABLE=1

.PHONY: all create_vm postgresql pgsql_replicas pacemaker prov clean check validate cts pcmk-stop


all: create_vm postgresql pgsql_replicas pacemaker cluster

create_vm:
	vagrant up

postgresql: pcmk-stop
	vagrant up --provision-with=postgresql

pgsql_replicas: pcmk-stop
	vagrant up --provision-with=pgsql-replicas

pacemaker:
	vagrant up --provision-with=pacemaker

cluster:
	vagrant up --provision-with=cluster-setup

prov:
	vagrant up --provision

clean:
	vagrant destroy -f

check: validate

validate:
	@vagrant validate
	@if which shellcheck >/dev/null                                          ;\
	then shellcheck provision/*bash                                          ;\
	else echo "WARNING: shellcheck is not in PATH, not checking bash syntax" ;\
	fi

cts:
	vagrant up --provision-with=cts

pcmk-stop:
	vagrant ssh -c 'if [ -f "/etc/corosync/corosync.conf" ]; then sudo pcs cluster stop --all --wait; fi'

