all: create_vm pgsql-replicas pacemaker

create_vm:
	vagrant up

pgsql-replicas:
	vagrant up --provision-with=pgsql-replicas

pacemaker:
	vagrant up --provision-with=pacemaker

prov:
	vagrant up --provision

clean:
	vagrant destroy -f

validate:
	vagrant validate

