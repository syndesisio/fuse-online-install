#!/bin/bash

# ====================================================
# Script for *updating* syndesis on OCP (including imagestreams)

# ================
# Target version to update to
TAG=1.4.9
# ================

# Minimal version for OC
OC_MIN_VERSION=3.9.0

# Image name prefix
IMAGE_NAME_PREFIX="fuse-ignite"

# Exit if any error occurs
# Fail on a single failed command in a pipeline (if supported)
set -o pipefail

# Fail on error and undefined vars (please don't use global vars, but evaluation of functions for return values)
set -eu

# Save global script args
ARGS=("$@")


display_usage() {
  cat <<EOT
Fuse Online Update Tool for OCP

Usage: update_ocp.sh [options]

with options:

   --version                  Print target version to update to and exit.
-v --verbose                  Verbose logging
EOT
}

# ============================================================
# Helper functions taken over from "syndesis" CLI:

# Dir where this script is located
basedir() {
    # Default is current directory
    local script=${BASH_SOURCE[0]}

    # Resolve symbolic links
    if [ -L $script ]; then
        if readlink -f $script >/dev/null 2>&1; then
            script=$(readlink -f $script)
        elif readlink $script >/dev/null 2>&1; then
            script=$(readlink $script)
        elif realpath $script >/dev/null 2>&1; then
            script=$(realpath $script)
        else
            echo "ERROR: Cannot resolve symbolic link $script"
            exit 1
        fi
    fi

    local dir=$(dirname "$script")
    local full_dir=$(cd "${dir}" && pwd)
    echo ${full_dir}
}

# Checks if a flag is present in the arguments.
hasflag() {
    filters="$@"

    if [[ ! -z ${ARGS+x} ]]; then
        for var in "${ARGS[@]}"; do
            for filter in $filters; do
              if [ "$var" = "$filter" ]; then
                  echo 'true'
                  return
              fi
            done
        done
    fi
}

# Read the value of an option.
readopt() {
    filters="$@"
    if [[ ! -z ${ARGS+x} ]]; then
        next=false
        for var in "${ARGS[@]}"; do
            if $next; then
                echo $var
                break;
            fi
            for filter in $filters; do
                if [[ "$var" = ${filter}* ]]; then
                    local value="${var//${filter}=/}"
                    if [ "$value" != "$var" ]; then
                        echo $value
                        return
                    fi
                    next=true
                fi
            done
        done
    fi
}


check_error() {
    local msg="$*"
    if [ "${msg//ERROR/}" != "${msg}" ]; then
        if [ -n "${ERROR_FILE:-}" ] && [ -f "$ERROR_FILE" ] && ! grep "$msg" $ERROR_FILE ; then
            local tmp=$(mktemp /tmp/error-XXXX)
            echo ${msg} >> $tmp
            if [ $(wc -c <$ERROR_FILE) -ne 0 ]; then
              echo >> $tmp
              echo "===============================================================" >> $tmp
              echo >> $tmp
              cat $ERROR_FILE >> $tmp
            fi
            mv $tmp $ERROR_FILE
        fi
        exit 0
    fi
}

print_error() {
    local error_file="${1:-}"
    if [ -f $error_file ]; then
        if grep -q "ERROR" $error_file; then
            cat $error_file
        fi
        rm $error_file
    fi
}

check_oc_version()
{
    local minimum=${OC_MIN_VERSION}
    local test=$(oc version | grep oc | tr -d oc\ v | cut -f1 -d "+")

    echo $(compare_oc_version $test $minimum)
}

setup_oc() {

    # Check path first if it already exists
    set +e
    which oc &>/dev/null
    if [ $? -eq 0 ]; then
      set -e
      err=$(check_oc_version)
      check_error $err
      return
    fi

    # Check for minishift
    which minishift &>/dev/null
    if [ $? -eq 0 ]; then
      set -e
      eval $(minishift oc-env)
      err=$(check_oc_version)
      check_error $err
      return
    fi

    set -e

    # Error, no oc found
    echo "ERROR: No 'oc' binary found in path. Please install the client tools from https://github.com/openshift/origin/releases/tag/v3.9.0 (or newer)"
    exit 1
}

compare_version_part() {
    local test=$1
    local min=$2

    test=`expr $test`
    min=`expr $min`

    if [ $test -eq $min ]; then
        echo 0;
    elif [ $test -gt $min ]; then
        echo 1;
    else
        # $test -lt $min
        echo -1
    fi
}

compare_oc_version() {
    local test=$1
    local min=$2

    echo -n "Testing oc version '$test' against required minimum '$min' ... "

    testparts=( ${test//./ } )
    minparts=( ${min//./ } )

    local i=0
    while [ $i -lt ${#minparts[@]} ]
    do
        local testpart=${testparts[$i]}
        local minpart=${minparts[$i]}

        if [ -z "$testpart" ]; then
            # test version does not extend as far as minimum
            # in parts so append a 0
            testpart=0
        fi

        ret=$(compare_version_part $testpart $minpart)
        if [ $ret == -1 ]; then
            #
            # version part is less than minimum while all preceding
            # parts were equal so version does not meet minimum
            #
            echo "ERROR: oc version ($test) should be at least $min"
            return
        elif [ $ret == 1 ]; then
            #
            # version part is greater than minimum so no need to test
            # any further parts as version is greater than minimum
            #
            echo "OK"
            return
        fi

        #
        # Only if the version part is equal will the loop continue
        # with further parts.
        #
        i=`expr $i + 1`
    done

    echo "OK"
}

check_syndesis() {
  # Check for a syndesis resource and update only if one exists
  set +e
  oc get syndesis >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "ERROR: No CRD Syndesis installed or no permissions to read them. Please run --setup and/or --grant as cluster-admin. Please use '--help' for more information."
    return
  fi
  set -e

  local nr=$(oc get syndesis -o name | wc -l | awk '$1=$1')
  if [ $nr -ne 1 ]; then
    echo "ERROR: Exactly 1 syndesis resource expected, but $nr found"
    return
  fi
}

extract_minor_tag() {
    local version=$1
    if [ "$version" == "master" ]; then
        echo "latest"
        return
    fi
    local minor_version=$(echo $version | sed 's/^\([0-9]*\.[0-9]*\)\.[0-9]*\(-.*\)*$/\1/')
    if [ "$minor_version" = "$version" ]; then
        echo "ERROR: Cannot extract minor version from $version"
        return
    fi
    echo $minor_version
}

ensure_image_streams() {
    local is_installed=$(oc get imagestream -o name | grep ${IMAGE_NAME_PREFIX}-server)
    if [ -n "$is_installed" ]; then
        local result=$(delete_openshift_resource "resources/fuse-online-image-streams.yml")
        check_error $result
    fi

    local result=$(create_openshift_resource "resources/fuse-online-image-streams.yml")
    check_error $result
}

create_openshift_resource() {
    create_or_delete_openshift_resource "create" "${1:-}"
}

delete_openshift_resource() {
    create_or_delete_openshift_resource "delete --ignore-not-found" "${1:-}"
}

create_or_delete_openshift_resource() {
    local what=${1}
    local resource=${2:-}
    local result

    set +e
    local url="https://raw.githubusercontent.com/syndesisio/fuse-online-install/${TAG}/${resource}"
    result=$(oc $what -f $url >$ERROR_FILE 2>&1)
    if [ $? -ne 0 ]; then
        echo "ERROR: Cannot create remote resource $url"
    fi
    set -e
}


has_istag() {
  set +e
  oc get istag ${1} -o name >/dev/null 2>&1
  if [ $? -eq 0 ]; then
      echo "true"
  else
      echo "false"
  fi
  set -e
}

update_imagestreams() {
  local tag="${1}"
  local minor_version="${2}"

  local istag=""
  if $(has_istag "${IMAGE_NAME_PREFIX}-server:$minor_version"); then
      istag="$minor_version"
  elif $(has_istag "${IMAGE_NAME_PREFIX}-server:$tag"); then
      istag="$tag"
  fi

  if [ -z "$istag" ]; then
      echo "No existing imagestreamtags found, assuming major update"
      ensure_image_streams
      return
  fi

  for image in "server" "ui" "meta" "s2i"; do
      local is=${IMAGE_NAME_PREFIX}-$image
      eval tag_image=\$tag_${image}

      import_image "$is:$tag_image" "$is:${istag}"
  done
}

import_image() {
    local source=${1}
    local target=${2}

    echo "Importing $source"
    local import_out="$(mktemp /tmp/oc-import-output-XXXXX)"
    trap "rm $import_out" EXIT
    oc tag --source docker "${registry}/${repository}/${source}" "${target}" >$import_out 2>&1
    sleep 5
    oc import-image "$target" --confirm="true" --from "${registry}/${repository}/${source}" >>$import_out 2>&1
    set +e
    if grep -q Error $import_out; then
        echo "Can't import"
        cat $import_out
        exit 1
    fi
    set -e
}

update_operator_imagestream() {
  local tag="${1}"
  local minor_version="${2}"

  local istag=""
  if $(has_istag "fuse-online-operator:$minor_version"); then
      istag="$minor_version"
  elif $(has_istag "fuse-online-operator:$tag"); then
      istag="$tag"
  fi

  if [ -z "$istag" ]; then
      echo "No existing operator tag found, assuming a major upgrade. Skipping update ..."
      // TODO: Import new major image stream and update deployment of the operator
      return
  fi

  import_image "fuse-online-operator:$tag_operator" "fuse-online-operator:${istag}"
}

# ==============================================================

if [ $(hasflag --help -h) ]; then
    display_usage
    exit 0
fi

ERROR_FILE="$(mktemp /tmp/syndesis-output-XXXXX)"
trap "print_error $ERROR_FILE" EXIT

if [ $(hasflag --verbose -v) ]; then
    export PS4='+($(basename ${BASH_SOURCE[0]}):${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -x
fi

# ==================================================================

# Read in config variables
source $(basedir)/fuse_online_config.sh

if [ $(hasflag --version) ]; then
    echo "Update to Fuse Online $TAG"
    echo
    echo "fuse-online-operator: $tag_operator"
    echo "${IMAGE_NAME_PREFIX}-server:   $tag_server"
    echo "${IMAGE_NAME_PREFIX}-ui:       $tag_ui"
    echo "${IMAGE_NAME_PREFIX}-meta:     $tag_meta"
    echo "${IMAGE_NAME_PREFIX}-s2i:      $tag_s2i"
    exit 0
fi

# Check the project
project=$(readopt --project -p)
if [ -z "${project}" ]; then
    project=$(oc project -q)
fi

# Check for OC
setup_oc

# Check whether there is an installation
check_error "$(check_syndesis)"

minor_tag=$(extract_minor_tag $TAG)

# Add new ImageStream tags from the version in fuse_online_config.sh
echo "Update imagestreams in $project"
update_imagestreams "$TAG" "$minor_tag"

# Update operator's image stream, which will trigger a redeployment
echo "Update operator imagestream"
update_operator_imagestream "$TAG" "$minor_tag"

cat <<EOT
========================================================
Congratulation, Fuse Online has been updated to $TAG !
