# fuse-online-install


## Installation

You can directly install from this repository for a specific fuse-online version.
Installation is performed with `install_ocp.sh`.
This script can be downloaded or executed directly from a cloned git repository:

```
# Execute directly for version 1.4.5
$ wget https://raw.githubusercontent.com/syndesisio/fuse-online-install/1.4.5/install_ocp.sh

# or git clone the repository and switch to tag 1.4.5
$ git clone https://github.com/syndesisio/fuse-online-install
$ cd fuse-online-install
$ git checkout 1.4.5
```

Installation of Fuse Online consiste of two steps:

1. You have to register first a custom resource on cluster level and allow a user to install Syndesis in his project. You need cluster admin permissions for this.
2. Fuse Online itself is then installed in a  second step, which is performed as a regular user.


### One-off admin action to register Custom Resource

For the first step you have to be connected as a *cluster admin* to the OCP cluster where you want install Fuse Online into.

Verify that you are properly connected and can list custom resources

```
$ oc get crd
```

When this command works for you without error you can call `install_ocp` to register the CRD on cluster level.

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
$ oc login developer
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

## Release
Installation templates and other objects for installing Red Hat Fuse Ignite (based on Syndesis)

Fuse Ignite can be installed in two flavors:

* Red Hat Fuse Ignite Online on OpenShift Online (OSO)
* Red Hat Fuse Ignite on OpenShift Cluster Platform (OCP)

This repository holds the corresponding templates and other resoruces which holds references to the Fuse Ignite product images.
These resources are extracted from the associated [syndesis](https://github.com/syndesisio/syndesis) upstream project.
A release is performed with the included `release.sh` script.

All configuration is set in `fuse_ignite_config.sh`:

```
# Git Tags:

# Upstream Syndesis release
git_syndesis="1.3.10"
# Tag to create for the templates
git_fuse_ignite_install="1.3.10-CR"

# Tags used for the productised images
tag_server="1.0-17"
tag_ui="1.0-22"
tag_meta="1.0-15"
tag_s2i="1.0-15"
tag_upgrade="1.0-18"

# Test:
registry="brew-pulp-docker01.web.prod.ext.phx2.redhat.com:8888"
repository="jboss-fuse-7-tech-preview"

# Official:
# local registry="registry.access.redhat.com"
# local repository="fuse7"
```

When the config file is setup a release is performed by simply calling `bash release.sh`. Some options are available, see below for which one.

The release process will perform the following steps (the variables are taken from `fuse_ignite_config.sh`):

* Clone https://github.com/syndesisio/syndesis
* Switch to tag `$git_syndesis`
* Recreate templates in the productised flavors. The templates created are `resources/fuse-ignite-ocp.yml` and `resources/fuse-ignite-oso.yml`
* Update `install_ocp.sh` with the tag from `$git_fuse_ignite_install`
* Insert tags from the config file into image stream template and store the processed file under `resources/fuse-ignite-image-streams.yml`
* Commit everything
* Git tag with `$git_fuse_ignite`
* Create a moving tag up to the minor number (e.g. 1.5) pointing to the tag just created
* Git push if `--git-push` is given

The imagestream which are installed for the OCP variant are included in `resources/fuse-ignite-image-streams.yml` and need to be updated manually for the moment for new releases.
The streams file needs to be updated before the release is started.

The script understands some additional options:

```
Release tool for fuse-ignite templats

Usage: bash release.sh [options]

with options:

--help                       This help message
--create-templates           Only create templates but do not commit or push
--git-push                   Push to git directly
--verbose                    Verbose log output

Please check also "fuse_ignite_config.sh" for the configuration values.
```

### Fuse Online Templates

The templates checked in and tagged with _regular_ tags in pure numeric form (e.g. `1.2.8`) are always referencing upstream images that are available at Docker Hub.

For a different setup to referencing different images (i.e. the images that are produced by the Red Hat productisation process), yet another set of templates can be generated.

For this the option `--product-templates` can be used, which generates templates _without image stream definitions_, but referencing supposedly already existing image streams.

These templates are created with a tag `fuse-ignite-<minor>` (e.g. `fuse-ignite-1.2`) in the Git repository and so can be directly accessed from GitHub.

An extra step is required to import productised Fuse Ignite Docker images into the Fuse Ignite cluster. This is described in the next section.

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
