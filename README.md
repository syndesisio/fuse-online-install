# fuse-ignite-install


## Installation

You can directly install from this repository for a specific fuse-ignite version.
Installation is performed with `install_ocp.sh`.
This script can be downloaded or executed directly from a cloned git repository:

```
# Execute directly for version 1.3.5
$ wget https://raw.githubusercontent.com/syndesisio/fuse-ignite-install/1.3.5/install_ocp.sh

# or git clone the repository and switch to tag 1.3.5
$ git clone https://github.com/syndesisio/fuse-ignite-install
$ cd fuse-ignite-install
$ git co 1.3.5
```

For this script to work you need to be connected to the OCP cluster where you want install Fuse Ignite into.
Verify that you are properly connected and check your current project:

```
$ oc project
```

When you call `install_ocp.sh` it will install Fuse Ignite in this current project.
You can choose a different project with the option `--project <project>`.
Please be aware that this project will be deleted if it already exists.

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
A release is performed with the included `release.sh` script which takes as option `--version-syndesis` the Git tag from syndesis from which the release should be performed.
This parameter is mandatory.
An optional second `--version-fuse-ignite` can be provided to specify the fuse-ignite release.
By default it's the same as `--version-syndesis`.

The release process will perform the following steps:

* Clone https://github.com/syndesisio/syndesis
* Switch to tag `--version-syndesis`
* Recreate templates in the productised flavors. The templates created are `resources/fuse-ignite-ocp.yml` and `resources/fuse-ignite-oso.yml`
* Update `install_ocp.sh` with the tag from `--version-fuse-ignite`
* Insert `--version-fuse-ignite` and `--version-brew` in image stream template and store the processed file under `resources/fuse-ignite-image-streams.yml`
* Commit everything
* Git tag with `--version-fuse-ignite`
* Create a moving tag up to the minor number (e.g. 1.5) pointing to the tag just created
* Git push if `--git-push` is given

The imagestream which are installed for the OCP variant are included in `resources/fuse-ignite-image-streams.yml` and need to be updated manually for the moment for new releases.
The streams file needs to be updated before the release is started.



### Fuse Online Templates

The templates checked in and tagged with _regular_ tags in pure numeric form (e.g. `1.2.8`) are always referencing upstream images that are available at Docker Hub.

For a different setup to referencing different images (i.e. the images that are produced by the Red Hat productisation process), yet another set of templates can be generated.

For this the option `--product-templates` can be used, which generates templates _without image stream definitions_, but referencing supposedly already existing image streams.

These templates are created with a tag `fuse-ignite-<minor>` (e.g. `fuse-ignite-1.2`) in the Git repository and so directly accessed from GitHub.

The product template support is currently very specific to the Fuse Ignite Cluster, which is used for the Technical Preview phase of Fuse Ignite.

So it is likely that it might change in the future.

NOTE: An extra step is required to import productised Syndesis Docker images into the Fuse Ignite cluster. This step should be documented here, and probably added to the release script.
