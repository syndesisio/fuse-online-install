# fuse-ignite-install


## Installation

You can directly install from this repository for a specific fuse-ignite version.

All you need is the GitHub tag for the release

You then can call:


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
