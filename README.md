# fuse-online-install


## Installation

You can directly install from this repository for a specific fuse-online version.
Installation is performed with `install_ocp.sh`.
This script can be downloaded or executed directly from a cloned git repository:

```
# or git clone the repository and switch to tag 1.8.0
$ git clone https://github.com/syndesisio/fuse-online-install
$ cd fuse-online-install
$ git checkout 1.8.0
```

Installation of Fuse Online consists of three steps:

1. You need setup authentication for `registry.redhat.io`. Fuse Online requires a pull secret named `syndesis-pull-secret` to be present (See https://access.redhat.com/RegistryAuthentication)

2. You have to register first a custom resource on cluster level and allow a user to install Syndesis in his project. You need cluster admin permissions for doing this.

3. Fuse Online itself is then installed in a third step, which is performed as a regular user.

### Registry Authentication

The install script will create an image pull secret in order to access images in the Red Hat registry (registry.redhat.io). If the secret is present, this step is skipped.

### One-off admin setup step

For the second step you have to be connected as a *cluster admin* to the OCP cluster where you want install Fuse Online into.

Verify that you are properly connected and can list custom resources

```
$ oc get crd
```

When this command works for you without error you can call `install_ocp.sh` to register the CRD on cluster level.

```
$ bash install_ocp.sh --setup
```

You can also grant permissions to a the user who will eventually install Fuse Online in his project.
In order to allow user `developer` to install Fuse Online into the currently connect project use

```
$ bash install_ocp.sh --grant developer
```

(You can read the current project with `oc project`). However, if the user deletes this project and recreates it, or want to install Fuse Online into a different project use the following command to grant cluster wide usage:

```
$ bash install_ocp.sh --grant developer --cluster
```

You can also combine both calls to a single call

```
$ bash install_ocp.sh --setup --grant developer --cluster
```

These steps need to be performed only once.
However, if you want to add additional users, just call `--grant` for each user to add.

### Install Fuse Online

If this setup has been performed successfully, you can switch to _admin user_ who you just have granted access (e.g. "developer" in the example above):

```
$ oc login -u developer
```

Then you can install Fuse Online with just

```
$ bash install_ocp.sh
```

You can use several options to tune the installation process.
Call `bash install_ocp.sh --help` for all options possible:

```
$ bash install_ocp.sh --help

Fuse Online Installation Tool for OCP

Usage: install_ocp.sh [options]

with options:

-s  --setup                   Install CRDs clusterwide. Use --grant if you want a specific user to be
                              able to install Fuse Online. You have to run this option once as cluster admin.
-u  --grant <user>            Add permissions for the given user so that user can install the operator
                              in her projects. You have to run this as cluster-admin
    --cluster                 Add the permission for all projects in the cluster
                              (only when used together with --grant)
   --force                    Override an existing installation if present
-p --project <project>        Install into this project. The project will be deleted
                              if it already exists. By default, install into the current project (without deleting)
   --skip-pull-secret         Skip the creation of the pull-secret. By default, will create or replace the pull-secret.
-w --watch                    Wait until the installation has completed
-o --open                     Open Fuse Online after installation (implies --watch)
                              (version is optional)
   --help                     This help message
-v --verbose                  Verbose logging

You have to run `--setup --grant <user>` as a cluster-admin before you can install Fuse Online as a user.
```


When you call `install_ocp.sh` it will install Fuse Online in this current project.
You can choose a different project with the option `--project <project>`.
Please be aware that this project will be deleted if it already exists.
Also, you must have used the option `--cluster` when you set up the CRDs.

### Example

The simplest way to install Fuse Ignite with no log URL enabled is

```
# Install with no link to the runtime pod's log
$ bash install_ocp.sh
```

For recreating the current project:

```
$ bash install_ocp.sh --project $(oc project -q)
```

## Update

For updating an existing installation you should use the script `update_ocp.sh`.
This script know the following options (which you get with `--help`):

```
Fuse Online Update Tool for OCP

Usage: update_ocp.sh [options]

with options:

   --skip-pull-secret         Skip the creation of the pull-secret. By default, will create or replace the pull-secret.
   --version                  Print target version to update to and exit.
-v --verbose                  Verbose logging
```

To start the update, call it without any option.
The installation will be updated to
the version to which this update script belogns.
Use `--version` to see what are you going to update to:

```
$ bash update_ocp.sh --version
Update to Fuse Online 1.8

syndesis-operator:  1.8.1-20190920
```

## Release

This section describes the release process.

A release is performed with the included `release.sh` script.

All configuration is set in `common_config.sh`:

```
# Tag for release. Update this before running release.sh
TAG_FUSE_ONLINE_INSTALL=1.8.0

# Fuse minor version (update it manually)
TAG=1.8

# Common settings
CURRENT_OS=$(get_current_os)
BINARY_FILE_EXTENSION=$(get_executable_file_extension)
OC_MIN_VERSION=3.9.0

# Syndesis settings
SYNDESIS_VERSION=1.8.1-20190920
SYNDESIS_BINARY=syndesis
SYNDESIS_GIT_ORG=syndesisio
SYNDESIS_GIT_REPO=syndesis
SYNDESIS_DOWNLOAD_URL=https://github.com/${SYNDESIS_GIT_ORG}/${SYNDESIS_GIT_REPO}/releases/download/${SYNDESIS_VERSION}/syndesis-${SYNDESIS_VERSION}-${CURRENT_OS}-64bit.tgz

```

When the config file is setup, a release is performed by simply calling `bash release.sh`. Some options are available, see below for which one.

The release process will perform the following steps (the variables are taken from `common_config.sh`):

* Commit everything
* Git tag with `$TAG_FUSE_ONLINE_INSTALL`
* Create a moving tag corresponding to the `$TAG` variable
* Git push if `--git-push` is given

The script understands some additional options:

```
Release tool for fuse-online OCP

Usage: bash release.sh [options]

with options:

--help                       This help message
--git-push                   Push to git directly
--verbose                    Verbose log output

Please check also "common_config.sh" for the configuration values.
```

### Importing images

You can easily import images from one registry to an OpenShift internal registry, where these images then appear as Imagestreams in the project which is called like the image's repo.

You call e.g. with

```
cd utils
perl ./import_images.pl --registry docker.io --repo fuseignitetest
```

where `--registry` is the target registry an `--repo` is the repository part of the target image name (default: `fuse-ignite`)

This script will pick up the version numbers defined in `fuse_online_config.sh` and should be called right after a release from a release tag, e.g.

```
# Be sure to be oc-connected with the target OpenShift cluster
$ oc login ...

# Clone repo
$ git clone https://github.com/syndesisio/fuse-online-install.git
$ cd fuse-online-install

# Checkout tag
$ git checkout 1.8.0

# Login into the target registry for your docker daemon
$ docker login -u $(oc whoami) -p $(oc whoami -t) mytarget.registry.openshift.com

# Import images
$ cd utils
$ perl import_images.pl --registry mytarget.registry.openshift.com
```
