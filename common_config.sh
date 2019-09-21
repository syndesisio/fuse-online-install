#!/bin/bash
#
# Global configuration for the install scripts

source $BASEDIR/base_functions.sh

# Tag for release. Update this before running release.sh
TAG_FUSE_ONLINE_INSTALL=1.8.0

# Fuse minor version (update it manually)
TAG=1.8

# Common settings
CURRENT_OS=$(get_current_os)
BINARY_FILE_EXTENSION=$(get_executable_file_extension)
OC_MIN_VERSION=3.9.0

# Camel K settings
CAMEL_K_VERSION=0.3.4
CAMEL_K_BINARY=kamel
CAMEL_K_GIT_ORG=jboss-fuse
CAMEL_K_GIT_REPO=camel-k
CAMEL_K_DOWNLOAD_URL=https://github.com/${CAMEL_K_GIT_ORG}/${CAMEL_K_GIT_REPO}/releases/download/${CAMEL_K_VERSION}/camel-k-client-${CAMEL_K_VERSION}-${CURRENT_OS}-64bit.tar.gz

# Syndesis settings
SYNDESIS_VERSION=1.8.1-20190920
SYNDESIS_BINARY=syndesis
SYNDESIS_GIT_ORG=nicolaferraro
SYNDESIS_GIT_REPO=syndesis
SYNDESIS_DOWNLOAD_URL=https://github.com/${SYNDESIS_GIT_ORG}/${SYNDESIS_GIT_REPO}/releases/download/${SYNDESIS_VERSION}/syndesis-${SYNDESIS_VERSION}-${CURRENT_OS}-64bit.tgz
