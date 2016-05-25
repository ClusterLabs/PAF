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

In `resource-agents-paf.spec`:
  * update the tag in the `_tag` variable (first line)
  * update the version in `Version:`
  * edit the changelog
    * date format: `LC_TIME=C date +"%a %b %d %Y"`

In `debian/`:
  * edit the `changelog` file
  * update the package name in `files`

## Tagging and building tar file

```
TAG=v1.0.0
git tag $TAG
git push --tags
git archive --prefix=PAF-$TAG/ -o /tmp/PAF-$TAG.tgz $TAG
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
  - upload the tar file
  - save

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

Don't forget to upload the package on github release page.

## Building the deb file

### Installation

```
apt-get install dh-make devscripts libmodule-build-perl resource-agents
```


### Building the package

Package to install on your debian host to build the builder environment

```
VER=1.0.0
wget "https://github.com/dalibo/PAF/releases/download/v${VER}/PAF-v${VER}.tgz" -O resource-agents-paf_${VER}.orig.tar.gz
tar zxf resource-agents-paf_${VER}.orig.tar.gz
mv PAF-v${VER}/ resource-agents-paf-${VER}
cd resource-agents-paf-${VER}
debuild -i -us -uc -b
```
Don't forget to upload the package on github release page.
