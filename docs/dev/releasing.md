# Releasing

## Source code

Edit varable `$VERSION` in the following files:

  * `script/pgsqlms`
  * `lib/OCF_Directories.pm.PL`
  * `lib/OCF_Functions.pm`
  * `lib/OCF_ReturnCodes.pm`

In `Build.PL`, search and edit the following line:

```
dist_version       => '1.0.0'
```

## Tagging and building tar file

```
TAG=v1.0.0
git tag $TAG
git push --tags
git archive --prefix=PAF-$TAG/ -o /tmp/PAF-$TAG.tgz $TAG
```

## Building the RPM file

### Installation

```
yum group install "Development Tools"
yum install rpmdevtools
useradd makerpm
```

### Building the package

```
su - makerpm
rpmdev-setuptree
git clone https://github.com/dalibo/PAF.git
spectool -R -g PAF/resource-agents-paf.spec
rpmbuild -ba PAF/resource-agents-paf.spec
```

## Release on github

  - go to https://github.com/dalibo/PAF/tags
  - edit the release notes for the new tag
  - set "PAF $VERSION" as title, eg. "PAF 1.0.0"
  - here is the format of the release node itself:
    YYYY-MM-DD -  Version X.Y.Z
    
    Changelog:
      * item 1
      * item 2
      * ...
      
      See http://dalibo.github.io/PAF/documentation.html
  - upload the tar file and the RPM file
  - save
