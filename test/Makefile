all: create_vm pgsql-replicas pacemaker

create_vm:
	vagrant up

pgsql-replicas:
	vagrant up --provision-with=pgsql-replicas

pacemaker:
	vagrant up --provision-with=pacemaker

pgsql-primary:
	vagrant up --provision-with=pgsql-primary

cts: all
	vagrant up --provision-with=cts

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

