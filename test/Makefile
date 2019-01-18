export VAGRANT_BOX_UPDATE_CHECK_DISABLE=1
export VAGRANT_CHECKPOINT_DISABLE=1

.PHONY: all create_vm pgsql-primary pgsql-replicas pacemaker cts prov clean validate


all: create_vm pgsql-replicas pacemaker

create_vm:
	vagrant up

pgsql-replicas:
	vagrant up --provision-with=pgsql-replicas

pacemaker:
	vagrant up --provision-with=pacemaker

pgsql-primary:
	vagrant up --provision-with=pgsql-primary

prov:
	vagrant up --provision

clean:
	vagrant destroy -f

validate:
	@vagrant validate
	@if which shellcheck >/dev/null                                          ;\
	then shellcheck provision/*                                              ;\
	else echo "WARNING: shellcheck is not in PATH, not checking bash syntax" ;\
	fi

cts: all
	vagrant up --provision-with=cts

