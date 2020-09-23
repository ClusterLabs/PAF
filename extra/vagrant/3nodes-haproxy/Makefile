export VAGRANT_BOX_UPDATE_CHECK_DISABLE=1
export VAGRANT_CHECKPOINT_DISABLE=1

.PHONY: all up pgsql pacemaker cts clean check validate pcmk-stop

all: up

up:
	vagrant up

pgsql: pcmk-stop
	vagrant provision --provision-with=pgsql

pacemaker:
	vagrant provision --provision-with=pacemaker

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
	vagrant provision --provision-with=cts

pcmk-stop:
	vagrant ssh -c 'if [ -f "/etc/corosync/corosync.conf" ]; then sudo pcs cluster stop --all --wait; fi'

