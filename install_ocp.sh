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
    --route                   Route to use. If not given, the route is trying to be detected from the currently
                              connected cluster.
   --console <console-url>    The URL to the openshift console
   --force                    Override an existing installation if present

-p --project <project>        Install into this project. The project will be deleted
                              if it already exists. By default, install into the current project (without deleting)
-w --watch                    Wait until the installation has completed
-o --open                     Open Fuse Online after installation (implies --watch)
   --camel-k                  Install also the camel-k operator
                              (version is optional)
   --camel-k-options "opts"   Options used when installing the camel-k operator.
                              Use quotes and start with a space before appending the options.
   --datavirt                 Install Data Virtualizations.
   --help                     This help message
-v --verbose                  Verbose logging

You have to run "--setup --grant <user>" as a cluster-admin before you can install Fuse Online as a user.
EOT
}

# ============================================================

# Create syndesis resource
create_syndesis() {
    local route="${1:-}"
    local console="${2:-}"
    local image_stream_namespace="${3:-}"

    local syndesis_installed=$(oc get syndesis -o name | wc -l)
    local force=$(hasflag --force)
    if [ $syndesis_installed -gt 0 ]; then
        if [ -n "${force}" ]; then
            oc delete $(oc get syndesis -o name)
        fi
    fi

    local syndesis=$(cat <<EOT
apiVersion: "syndesis.io/v1alpha1"
kind: "Syndesis"
metadata:
  name: "app"
spec:
  integration:
    # No limitations by default on OCP
    limit: 0
EOT
)
    local extra=""
    if [ -n "$console" ]; then
        extra=$(cat <<EOT

  openshiftConsoleUrl: "$console"
EOT
)
        syndesis="${syndesis}${extra}"
    fi

    if [ -n "$route" ]; then
        extra=$(cat <<EOT

  routeHostname: "$route"
EOT
)
        syndesis="${syndesis}${extra}"
    fi

    if [ -n "$image_stream_namespace" ]; then
        extra=$(cat <<EOT

  imageStreamNamespace: "$image_stream_namespace"
EOT
)
        syndesis="${syndesis}${extra}"
    fi

    local datavirt=$(hasflag --datavirt)
    if [ -n "${datavirt}" ]; then
        extra=$(cat <<EOT

  addons:
    komodo:
      enabled: "true"
EOT
)
        syndesis="${syndesis}${extra}"
    fi

    local camelk=$(hasflag --camel-k)
    if [ -n "${camelk}" ]; then
        extra=$(cat <<EOT

  addons:
    camelk:
      enabled: "true"
EOT
)
        syndesis="${syndesis}${extra}"
    fi

    echo "$syndesis" | cat | oc create -f -
    if [ $? -ne 0 ]; then
        echo "ERROR: Error while creating resource"
        echo "$syndesis"
        return
    fi
}



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

# ==============================================================

if [ $(hasflag --help -h) ]; then
    display_usage
    exit 0
fi

if [ $(hasflag --verbose -v) ]; then
    export PS4='+($(basename ${BASH_SOURCE[0]}):${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -x
fi

prep_only="false"
if [ $(hasflag -s --setup) ]; then
    echo "Installing Syndesis CRD"

    $SYNDESIS_CLI install cluster

    if [ $(hasflag --camel-k) ]; then
      echo "Installing Camel-K CRDs"

      $KAMEL_CLI install --cluster-setup
    fi
    prep_only="true"
fi

user_to_prepare="$(readopt -u --grant)"
if [ -n  "$user_to_prepare" ]; then
    echo "Grant permission to create Syndesis to user $user_to_prepare"
    clusterwide=""
    if [ $(hasflag --cluster) ]; then
      clusterwide="--cluster"
    fi
    $SYNDESIS_CLI grant --user "$user_to_prepare" $clusterwide
    prep_only="true"
fi

if $prep_only; then
    exit 0
fi

# Check for OC
setup_oc

# ==================================================================
# make sure pull secret is present (required since 7.3)
create_secret_if_not_present

# ==================================================================

# If a project is given, create it new or recreate it
project=$(readopt --project -p)
if [ -n "${project}" ]; then
    recreate_project $project
else
    project=$(oc project -q)
fi

# Check for the proper setup
set +e
oc get syndesis >/dev/null 2>&1
if [ $? -ne 0 ]; then
    check_error "ERROR: No CRD Syndesis installed or no permissions to read them. Please run --setup and/or --grant as cluster-admin. Please use '--help' for more information."
fi

if [ $(hasflag --camel-k) ]; then
    oc get integration >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        check_error "ERROR: Camel-K installation requested but no Camel-K CRDs accessible. Please run --setup --camel-k to register the proper CRDs."
    fi
fi
set -e


# Deploy operator and wait until its up
echo "Deploying Syndesis operator"
$SYNDESIS_CLI install operator

if [ $(hasflag --camel-k) ]; then
    echo "Deploying Camel-K operator"
    $KAMEL_CLI install --skip-cluster-setup $(readopt --camel-k-options)

    result=$(oc secrets link camel-k-operator syndesis-pull-secret --for=pull >$ERROR_FILE 2>&1)
    check_error $result
fi

# Wait for deployment
wait_for_deployments 1 syndesis-operator

# Create syndesis resource
echo "Creating Syndesis resource"
route=$(readopt --route)
console=$(readopt --console)
result=$(create_syndesis "$route" "$console" "$project")
check_error "$result"

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
