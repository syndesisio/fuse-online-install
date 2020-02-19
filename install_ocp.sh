#!/bin/bash

# ====================================================
# Standalone script for deploying syndesis on OCP (including imagestreams)

# Exit if any error occurs
# Fail on a single failed command in a pipeline (if supported)
set -o pipefail

# Fail on error and undefined vars (please don't use global vars, but evaluation of functions for return values)
set -eu

# Save global script args
ARGS=("$@")

DEFAULT_CR_FILE="./default-cr.yml"

# Helper functions:

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

# Getting base dir
BASEDIR=$(basedir)

# Get configuration and other scripts
pushd > /dev/null . && cd $BASEDIR
source $BASEDIR/base_functions.sh
source $BASEDIR/common_config.sh
source $BASEDIR/libs/download_functions.sh
source $BASEDIR/libs/openshift_functions.sh
popd > /dev/null

SYNDESIS_CLI=$(get_syndesis_bin)
check_error $SYNDESIS_CLI

# Download binary files
KAMEL_CLI=$(get_kamel_bin)
check_error $KAMEL_CLI

display_usage() {
  cat <<EOT
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
-w --watch                    Wait until the installation has completed
-o --open                     Open Fuse Online after installation (implies --watch)
                              (version is optional)
   --help                     This help message
-v --verbose                  Verbose logging

You have to run "--setup --grant <user>" as a cluster-admin before you can install Fuse Online as a user.
EOT
}

# ============================================================
open_url() {
    local url=$1
    local cmd="$(probe_commands open xdg-open chrome firefox)"
    if [ -z "$cmd" ]; then
        echo "Cannot find command for opening URL:"
        echo $url
        exit 1
    fi
    exec $cmd $url
}

probe_commands() {
    for cmd in $@; do
      local ret=$(which $cmd 2>/dev/null)
      if [ $? -eq 0 ]; then
          echo $ret
          return
      fi
    done
}

get_route_when_ready() {
    local name="${1}"
    local route=$(get_route $name)
    while [ -z "$route" ]; do
        sleep 10
        route=$(get_route $name)
    done
    echo $route
}

get_route() {
  local name="${1}"
  oc get route $name -o jsonpath="{.spec.host}" 2>/dev/null
}

grant_role() {
  local user_to_prepare="$1"
  if [ -z "$user_to_prepare" ]; then
    check_error "ERROR: Cannot perform grant as no user specified"
  fi

  echo "Grant syndesis-installer role to user $user_to_prepare"

  #
  # Check that the user calling --grant is a cluster-admin
  #
  if [ $(is_cluster_admin) != "OK" ]; then
    check_error "ERROR: Can only execute --grant as cluster-admin."
  fi

  clusterwide=""
  if [ $(hasflag --cluster) ]; then
    clusterwide="--cluster"
  fi

  set +e
  $SYNDESIS_CLI grant --user "$user_to_prepare" $clusterwide
  set -e
}

# ==============================================================

if [ $(hasflag --help -h) ]; then
    display_usage
    exit 0
fi

if [ $(hasflag --verbose -v) ]; then
    export PS4='+($(basename ${BASH_SOURCE[0]}):${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -x
fi

#
# Is the user executing this a cluster-admin?
#
cluster_admin=$(is_cluster_admin)
if [ "${cluster_admin}" == "OK" ]; then
  echo "User $(oc whoami) is a cluster-admin"
fi

#
# If a project is given, only a cluster-admin
# can create it new or recreate it
#
project=$(readopt --project -p)
if [ -n "${project}" ]; then
  if [ "$cluster_admin" == "OK" ]; then
    recreate_project $project
  else
    check_error "ERROR: It is not possible to install into a new (or recreated) project without being a cluster-admin since artifacts required by the install cannot be (re)created."
  fi
fi

prep_only="false"
if [ $(hasflag -s --setup) ]; then
    echo "Installing Syndesis CRD"

    #
    # Check that the user calling --setup is a cluster-admin
    #
    if [ "$cluster_admin" != "OK" ]; then
      check_error "ERROR: Can only execute --setup as cluster-admin."
    fi

    $SYNDESIS_CLI install cluster

    #
    # As camel-k addon may well be used we install these anyway
    #
    echo "Installing Camel-K CRDs"
    $KAMEL_CLI install --cluster-setup
    prep_only="true"
fi

user_to_prepare="$(readopt -u --grant)"
if [ -n  "$user_to_prepare" ]; then
    grant_role "$user_to_prepare"
    prep_only="true"
fi

if $prep_only; then
    exit 0
fi

# ===========================
#
# Do some pre-flight install checks
#
# ===========================

#
# Check for oc
#
setup_oc

#
# make sure pull secret is present (required since 7.3)
#
create_secret_if_not_present

#
# If a cluster-admin and the role has not yet been granted
# then ensure it is by grant it to the current user
#
if [ "$cluster_admin" == "OK" ]; then
  if [ "$(is_role_granted)" != "OK" ]; then
    echo "No syndesis-installer role has been granted so installing now"
    grant_role "$(oc whoami)"
  fi
fi

#
# Check that user has syndesis-installer role available
#
result=$(is_role_granted)
check_error "$result"

#
# Check CRD installed
#
set +e
oc get syndesis >/dev/null 2>&1
if [ $? -ne 0 ]; then
    check_error "ERROR: No CRD Syndesis installed or no permissions to read them. Please run --setup and/or --grant as cluster-admin. Please use '--help' for more information."
fi

oc get integration >/dev/null 2>&1
if [ $? -ne 0 ]; then
    check_error "ERROR: Failure to install Camel-K CRDs."
fi
set -e

# Deploy operator and wait until its up
echo "Deploying Syndesis operator"
$SYNDESIS_CLI install operator

set +e
result=$(oc secrets link syndesis-operator syndesis-pull-secret --for=pull >$ERROR_FILE 2>&1)
check_error $result
set -e

# Wait for deployment
wait_for_deployments 1 syndesis-operator

# Check syndesis cr already installed. If force then remove first.
syndesis_installed=$(oc get syndesis -o name | wc -l)
force=$(hasflag --force)
if [ $syndesis_installed -gt 0 ]; then
    echo "Warning ... Syndesis custom resource already installed: '${syndesis_installed}'"
    if [ -n "${force}" ]; then
        echo "Removing already installed Syndesis custom resource"
        oc delete $(oc get syndesis -o name)
    fi
fi

# Create syndesis resource
echo "Creating Syndesis with fuse-online resource"
if [ ! -f "${DEFAULT_CR_FILE}" ]; then
    echo "Cannot custom-resource file '$DEFAULT_CR_FILE' ... exiting."
    exit 1
fi

set +e
result=$($SYNDESIS_CLI install app --custom-resource ${DEFAULT_CR_FILE})
check_error $result
set -e

if [ $(hasflag --watch -w) ] || [ $(hasflag --open -o) ]; then
    wait_for_deployments 1 syndesis-server syndesis-ui syndesis-meta
fi

# ==========================================================

echo "Getting Syndesis route"
route=$(get_route_when_ready "syndesis")

cat <<EOT
========================================================
Congratulation, Fuse Online $TAG has been installed successfully !
Open now your browser at the following URL:

https://$route

Enjoy !
EOT

if [ $(hasflag --open -o) ]; then
    open_url "https://$route"
fi
