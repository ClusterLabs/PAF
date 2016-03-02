# How to build the RPM file

## Installation

```
yum group install "Development Tools"
yum install rpmdevtools
useradd makerpm
```

## Building the package

```
su - makerpm
rpmdev-setuptree
git clone https://github.com/dalibo/PAF.git
spectool -R -g PAF/resource-agents-paf.spec
rpmbuild -ba PAF/resource-agents-paf.spec
```


