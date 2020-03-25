#!/bin/bash
#
# Global configuration for the install scripts

source $BASEDIR/base_functions.sh

# Tag for release. Update this before running release.sh
TAG_FUSE_ONLINE_INSTALL=1.9.9

# Fuse minor version (update it manually)
TAG=1.9

# Common settings
CURRENT_OS=$(get_current_os)
BINARY_FILE_EXTENSION=$(get_executable_file_extension)
OC_MIN_VERSION=3.9.0

COMMON_RELEASE_GIT_ORG=jboss-fuse
COMMON_RELEASE_GIT_REPO=fuse-clients
BIN_TAG_PREFIX=

# Camel K settings
CAMEL_K_VERSION=$TAG_FUSE_ONLINE_INSTALL
CAMEL_K_BINARY=kamel
CAMEL_K_GIT_ORG=$COMMON_RELEASE_GIT_ORG
CAMEL_K_GIT_REPO=$COMMON_RELEASE_GIT_REPO
CAMEL_K_DOWNLOAD_URL=https://github.com/${CAMEL_K_GIT_ORG}/${CAMEL_K_GIT_REPO}/releases/download/${BIN_TAG_PREFIX}${CAMEL_K_VERSION}/camel-k-client-${CAMEL_K_VERSION}-${CURRENT_OS}-64bit.tar.gz
CAMEL_K_IMAGE=registry-proxy.engineering.redhat.com/rh-osbs/fuse7-tech-preview-fuse-camel-k-operator:1.6

# Syndesis settings
SYNDESIS_VERSION=$TAG_FUSE_ONLINE_INSTALL
SYNDESIS_BINARY=syndesis-operator
SYNDESIS_GIT_ORG=$COMMON_RELEASE_GIT_ORG
SYNDESIS_GIT_REPO=$COMMON_RELEASE_GIT_REPO
SYNDESIS_DOWNLOAD_URL=https://github.com/${SYNDESIS_GIT_ORG}/${SYNDESIS_GIT_REPO}/releases/download/${BIN_TAG_PREFIX}${SYNDESIS_VERSION}/syndesis-${SYNDESIS_VERSION}-${CURRENT_OS}-64bit.tar.gz
SYNDESIS_IMAGE=registry-proxy.engineering.redhat.com/rh-osbs/fuse7-fuse-online-operator:1.6
