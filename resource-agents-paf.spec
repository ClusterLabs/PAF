%global _tag v1.0.2
%global _ocfroot /usr/lib/ocf
Name: resource-agents-paf
Version: 1.0.2
Release: 1
Summary: PostgreSQL resource agent for Pacemaker
License: PostgreSQL
Group: Applications/Databases
Url: http://dalibo.github.io/PAF/

Source0: https://github.com/dalibo/PAF/releases/download/%{_tag}/PAF-%{_tag}.tgz
BuildArch: noarch
#BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildRequires: resource-agents perl perl-Module-Build
Provides: resource-agents-paf = %{version}

%description
PostgreSQL resource agent for Pacemaker

%prep
%setup -n PAF-%{_tag}

%build
perl Build.PL --destdir "%{buildroot}" --install_path bindoc=%{_mandir}/man1 --install_path libdoc=%{_mandir}/man3
perl Build

%install
./Build install
rm -f "%{buildroot}"/usr/local/lib64/perl5/auto/PAF/.packlist

%files
%defattr(-,root,root,0755)
%doc README.md 
%license LICENSE
%{_mandir}/man1/*.1*
%{_mandir}/man3/*.3*
%{_ocfroot}/resource.d/heartbeat/pgsqlms
%{_ocfroot}/lib/heartbeat/OCF_ReturnCodes.pm
%{_ocfroot}/lib/heartbeat/OCF_Directories.pm
%{_ocfroot}/lib/heartbeat/OCF_Functions.pm
%{_datadir}/resource-agents/ocft/configs/pgsqlms

%changelog
* Wed May 25 2016 Jehan-Guillaume de Rorthais <jgdr@dalibo.com> - 1.0.2-1
- 1.0.2 minor release
- fix: unknown argument --query when calling crm_master
- fix: perl warning when master score has never been set on the master
- change: remove misleading message in log file

* Wed Apr 27 2016 Jehan-Guillaume de Rorthais <jgdr@dalibo.com> - 1.0.1-1
- 1.0.1 minor release
- fix: forbid the master to decrease its own score (gh #19)
- fix: bad LSN decimal converstion (gh #20)
- fix: support PostgreSQL 9.5 controldata output (gh #12)
- fix: set group id of given system_user before executing commands (gh #11)
- fix: use long argument of external commands when possible
- fix: bad header leading to wrong manpage section
- fix: OCF tests when PostgreSQL does not listen in /tmp
- change: do not update score outside of a monitor action (gh #18)
- new: add parameter 'start_opts', usefull for debian and derivated (gh #11)
- new: add specific timeout for master and slave roles in meta-data (gh #14)
- new: add debian packaging related files

* Wed Mar 02 2016 Jehan-Guillaume de Rorthais <jgdr@dalibo.com> 1.0.0-1
- Official 1.0.0 release

* Tue Mar 01 2016 Jehan-Guillaume de Rorthais <jgdr@dalibo.com> 0.99.0-1
- Initial version

