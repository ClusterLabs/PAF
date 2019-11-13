# Releasing

## Source code

Edit varable `$VERSION` in the following files:

  * `script/pgsqlms`
  * `lib/OCF_Directories.pm.PL`
  * `lib/OCF_Functions.pm`
  * `lib/OCF_ReturnCodes.pm`

In `Build.PL`, search and edit the following line:

```
dist_version       => '1.0.0',
release_status     => 'stable',
```

For beta or rc release, set `release_status => 'testing'`.

In `resource-agents-paf.spec`:
  * update the tag in the `_tag` variable (first line)
  * update the version in `Version:`. for beta or rc release, use X.Y~betaZ or X.Y~rcZ
  * edit the changelog
    * date format: `LC_TIME=C date +"%a %b %d %Y"`
  * take care of the `Release` field if there is multiple version of the package
    for the same version of PAF

In `debian/`, edit the `changelog` file.

Edit the `CHANGELOG.md` file.

## Commit the changes

Check tat every issues related to this release has been closed!

```
git commit -m 'vX.Y.0 release'
```

For beta or rc release use `vX.Y_betaN` or `vX.Y_rcN`, eg. `v2.2_beta1`.

## Tagging and building tar file

```
TAG=v1.0.0
git tag $TAG
git push --tags
git archive --prefix=PAF-$TAG/ -o /tmp/PAF-$TAG.tgz $TAG
```

For beta or rc release use `vX.Y_betaN` or `vX.Y_rcN`, eg. `v2.2_beta1`.

## Release on github

  - go to https://github.com/ClusterLabs/PAF/tags
  - edit the release notes for the new tag
  - set "PAF $VERSION" as title, eg. "PAF 1.0.0"
  - here is the format of the release node itself:
    YYYY-MM-DD -  Version X.Y.Z
    
    Changelog:
      * item 1
      * item 2
      * ...
      
      See http://clusterlabs.github.io/PAF/documentation.html
  - upload the tar file
  - save

## Building the RPM file

### Installation

```
yum group install "Development Tools"
yum install rpmdevtools
useradd makerpm
```

### Building the package

```
su - makerpm
rpmdev-setuptree
git clone https://github.com/ClusterLabs/PAF.git
spectool -R -g PAF/resource-agents-paf.spec
rpmbuild -ba PAF/resource-agents-paf.spec
```

Don't forget to upload the package on github release page.

## Building the deb file

### Installation

```
apt-get install dh-make devscripts libmodule-build-perl resource-agents
```


### Building the package

Package to install on your debian host to build the builder environment

```
VER=1.0.0
wget "https://github.com/ClusterLabs/PAF/archive/v${VER/\~/_}.tar.gz" -O resource-agents-paf_${VER}.orig.tar.gz
mkdir resource-agents-paf-$VER
tar zxf resource-agents-paf_${VER}.orig.tar.gz -C "resource-agents-paf-$VER" --strip-components=1
cd resource-agents-paf-${VER}
debuild -i -us -uc -b
```

For beta or rc release, use `VER=X.Y~betaN` or `VER=X.Y~rcN`.

Don't forget to upload the package on github release page.

## Documentation

Update the "quick start" documentation pages with the links to the new packages  


## Community

* if this is a first beta or a release:
  - submit a news on postgrsql.org website
  - submit a mail on pgsql-announce mailing list
* submit a mail to the users@clusterlabs.org mailing list
* twitt, blog, ...
