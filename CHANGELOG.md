# PAF v2.2 beta1

Release date: WIP

__WARNING__: This version is only compatible with at least
Pacemaker 1.1.13 using a corosync 2.x stack.

Changelog since 2.1:

* new: support PostgreSQL 10, ioguix
* new: add the maxlag parameter to exclude lagging slaves from promotion, Thomas Reiss
* new: support for multiple pgsqlms resources in the same cluster
* fix: follow the resource agent man page naming policy and section, ioguix
* fix: add documentation to the pgsqlms man page, ioguix
* fix: do not rely on crm_failcount, suggested on the clusterlabs lists, ioguix
* misc: improve the RPM packaging, ioguix
* misc: check Pacemaker compatibility and resource setup, ioguix
* misc: enforce the election process by including timelines comparison
* misc: various code cleanup, factorization and module improvement


# PAF v2.1.0

Release date: 2016-12-23

__WARNING__: This version is only compatible with at least
Pacemaker 1.1.13 using a corosync 2.x stack.

Changelog since 2.0:

* fix: compatibility with PostrgeSQL 9.6, YanChii
* change: better handling of Pacemaker timeout, ioguix with a fix from YanChii
* change: avoid fatal error during validate action when possible, Benoit Lobréau & ioguix
* new: parameter "datadir" to cope with PostgreSQL GUC data_directory, Benoit Lobréau & ioguix
* misc: improve debian packaging, Christoph Berg



# PAF v2.0.0

Release date: 2016-09-16

__WARNING__: This version is only compatible with at least
Pacemaker 1.1.13 using a corosync 2.x stack.

* 2.0.0 major release
* fix: do not use crm_node --partition to discover resources
* fix: unknown argument --query when calling crm_master
* fix: perl warning when master score has never been set on the master
* fix: remove wrong info message during post-promote notify
* fix: race condition when setting attributes during actions
* fix: bug where pgport and pghost where ignored in _query
* fix: use same role name than the system_user to connect
* fix: wrap crm_master calls in sub to make them synchronous
* fix: fixed a bug related to setgid in _runas
* fix: check on application_name in validate_all
* change: do not start standby with a master score of 1
* change: choose the clone to promote when no master score exist
* new: detect and deal master/slave recovery transition
* new: detect and enforce reliability of a switchover
* new: set next best secondaries base on their lag
* misc: code cleanup and refactoring
* misc: various log messages cleanup and enhancement



# PAF v1.0.2

Release date: 2016-05-25

* 1.0.2 minor release
* fix: unknown argument --query when calling crm_master
* fix: perl warning when master score has never been set on the master
* change: remove misleading message in log file



# PAF v1.0.1

Release date: 2016-04-27

* 1.0.1 minor release
* fix: forbid the master to decrease its own score (gh #19)
* fix: bad LSN decimal converstion (gh #20)
* fix: support PostgreSQL 9.5 controldata output (gh #12)
* fix: set group id of given system_user before executing commands (gh #11)
* fix: use long argument of external commands when possible
* fix: bad header leading to wrong manpage section
* fix: OCF tests when PostgreSQL does not listen in /tmp
* change: do not update score outside of a monitor action (gh #18)
* new: add parameter 'start_opts', usefull for debian and derivated (gh #11)
* new: add specific timeout for master and slave roles in meta-data (gh #14)
* new: add debian packaging related files



# PAF v1.0.0

Release date: 2016-03-02

* First public release

