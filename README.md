# fuse-online-install


## Installation

You can directly install from this repository for a specific fuse-online version.
Installation is performed with `install_ocp.sh`.
This script can be downloaded or executed directly from a cloned git repository:

```
# Execute directly for version 1.4.8
$ wget https://raw.githubusercontent.com/syndesisio/fuse-online-install/1.4.8/install_ocp.sh

# or git clone the repository and switch to tag 1.4.8
$ git clone https://github.com/syndesisio/fuse-online-install
$ cd fuse-online-install
$ git checkout 1.4.8
```

Installation of Fuse Online consists of three steps:

1. You need setup authentication for `registry.redhat.io`. Fuse Online requires a pull secret named `syndesis-pull-secret` to be present (See https://access.redhat.com/RegistryAuthentication)
2. You have to register first a custom resource on cluster level and allow a user to install Syndesis in his project. You need cluster admin permissions for doing this.
3. Fuse Online itself is then installed in a third step, which is performed as a regular user.

### Registry Authentication

First you need create an image pull secret, to be able to access images in the Red Hat registry (registry.redhat.io). The secret needs to be named `syndesis-pull-secret` and present in the namespace where you want to install Fuse Online:

```
oc create secret docker-registry syndesis-pull-secret \
    --docker-server=registry.redhat.io \
    --docker-username=<user> \
    --docker-password=<pass>
```

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

Syndesis Installation Tool for OCP

Usage: syndesis-install [options]

with options:

-s  --setup                   Install CRDs clusterwide. Use --grant if you want a specific user to be
                              able to install Fuse Online. You have to run this option once as cluster admin.
-u  --grant <user>            Add permissions for the given user so that user can install the operator
                              in her projects. You have to run this as cluster-admin
    --cluster                 Add the permission for all projects in the cluster
                              (only when used together with --grant)
    --route                   Route to use. If not given, the route is trying to be detected from the currently
                              connected cluster.
   --console <console-url>    The URL to the openshift console
   --force                    Override an existing installation if present

-p --project <project>        Install into this project. The project will be deleted
                              if it already exists. By default, install into the current project (without deleting)
-w --watch                    Wait until the installation has completed
-o --open                     Open Fuse Online after installation (implies --watch)
   --help                     This help message
-v --verbose                  Verbose logging
```


When you call `install_ocp.sh` it will install Fuse Online in this current project.
You can choose a different project with the option `--project <project>`.
Please be aware that this project will be deleted if it already exists.
Also, you must have used the option `--cluster` when you set up the CRDs.

The route under which Fuse Ignite can be reached will be calculated by default with some heuristics.
When this should fail or when you want to be more specific you can specify the route explicitly with `--route`.

One specific feature needs also some additional configuration: For enabling a link to an integration's runtime log in "Activity" tab, the URL to the OpenShift console must be provided with `--console`

### Example

The simplest way to install Fuse Ignite with an autodected route an no log URL enabled is

```
# Install with an autodetected route and no link to the runtime pod's log
$ bash install_ocp.sh
```

For recreating the current project, specifying an explicit route and OpenShift console URL explicitely use:

```
$ bash install_ocp.sh \
       --project $(oc project -q) \
       --route $(oc project -q).6a63.fuse-ignite.openshiftapps.com \
       --console https://console.fuse-ignite.openshift.com/console
```

### Options

The `install_ocp.sh` knows the following options (in addition to the main options described above):

```
Syndesis Installation Tool for OCP

Usage: syndesis-install [--route <hostname>] [--console <console-url>] [options]

with options:

-r --route <host>            The route to install (mandatory)
   --console <console-url>   The URL to the openshift console
-p --project <project>       Install into this project. The project will be deleted
                             if it already exists. By default, install into the current
                             project (without deleting)
-w --watch                   Wait until the installation has completed
-o --open                    Open Syndesis after installation (implies --watch)
   --help                    This help message
-v --verbose                 Verbose logging
```

## Update

For updating an existing installation you should use the script `update_ocp.sh`.
This script know the following options (which you get with `--help`):

```
Fuse Online Update Tool for OCP

Usage: update_ocp.sh [options]

with options:

   --version                  Print target version to update to and exit.
-v --verbose                  Verbose logging
```

To start the update, call it without any option.
The installation will be updated to
the version to which this update script belogns.
Use `--version` to see what are you going to update to:

```
$ bash update_ocp.sh --version
Update to Fuse Online version 1.4.9

fuse-ignite-server: 1.1-13
fuse-ignite-ui:     1.1-8
fuse-ignite-meta:   1.1-12
fuse-ignite-s2i:    1.1-13
```

## Release

This section describes the release process.
Each tag of this repository corresponds to the same tag in syndesisio/syndesis.
A release consists of a set of files created in the `resources/` directory and updating the `install_ocp.sh` script to point to the proper release version.

A release is performed with the included `release.sh` script.

All configuration is set in `fuse_ignite_config.sh`:

```
# Git Tags:

# Upstream Syndesis release
git_syndesis="1.4.8"

# Tags used for the productised images
tag_server="1.1-17"
tag_ui="1.1-22"
tag_meta="1.1-15"
tag_s2i="1.1-15"
tag_upgrade="1.1-18"

# Test & Staging:
registry="brew-pulp-docker01.web.prod.ext.phx2.redhat.com:8888"
repository="jboss-fuse-7-tech-preview"

# Official:
# local registry="registry.access.redhat.com"
# local repository="fuse7"
```

When the config file is setup a, release is performed by simply calling `bash release.sh`. Some options are available, see below for which one.

The release process will perform the following steps (the variables are taken from `fuse_ignite_config.sh`):

* Create resources by using the templates in `templates/` and substituting the version numbers from `fuse_online_config.sh`
* Extract the Fuse Online template from the operator image with the proper version. **Note**: The template must be used for legacy setups, but not for an operator based installation.
* Update `install_ocp.sh` with the tag from `$git_fuse_ignite_install`
* Commit everything
* Git tag with `$git_fuse_ignite`
* Create a moving tag up to the minor number (e.g. 1.4) pointing to the tag just created
* Git push if `--git-push` is given

The imagestream which are installed for the OCP variant are included in `resources/fuse-online-image-streams.yml` and need to be updated manually for the moment for new releases.
The streams file needs to be updated before the release is started.

The script understands some additional options:

```
Release tool for fuse-online OCP

Usage: bash release.sh [options]

with options:

--help                       This help message
--git-push                   Push to git directly
--verbose                    Verbose log output

Please check also "fuse_ignite_config.sh" for the configuration values.
```

### Importing images

You can easily import images from one registry to an OpenShift internal registry, where these images then appear as Imagestreams in the project which is called like the image's repo.

You call e.g. with

```
perl ./import_images.pl --registry docker.io --repo fuseignitetest
```

where `--registry` is the target registry an `--repo` is the repository part of the target image name (default: `fuse-ignite`)

This script will pick up the version numbers defined in `fuse_ignite_config.sh` and should be called right after a release from a release tag, e.g.

```
# Be sure to be oc-connected with the target OpenShift cluster
$ oc login ...

# Clone repo
$ git clone https://github.com/syndesisio/fuse-ignite-install.git
$ cd fuse-ignite-install

# Checkout tag
$ git checkout 1.3.11

# Login into the target registry for your docker daemon
$ docker login -u $(oc whoami) -p $(oc whoami -t) mytarget.registry.openshift.com

# Import images
$ perl import_images.pl --registry mytarget.registry.openshift.com
```
