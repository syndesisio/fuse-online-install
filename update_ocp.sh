#!/bin/bash

# ====================================================
# Script for *updating* Syndesis on OCP

# Exit if any error occurs
# Fail on a single failed command in a pipeline (if supported)
set -o pipefail

# Fail on error and undefined vars (please don't use global vars, but evaluation of functions for return values)
set -eu

# Save global script args
ARGS=("$@")

# Helper functions

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
pushd > /dev/null . && cd "$BASEDIR"
source "$BASEDIR/base_functions.sh"
source "$BASEDIR/common_config.sh"
source "$BASEDIR/libs/download_functions.sh"
source "$BASEDIR/libs/openshift_functions.sh"
popd > /dev/null

SYNDESIS_CLI=$(get_syndesis_bin)
check_error $SYNDESIS_CLI

display_usage() {
  cat <<EOT
Fuse Online Update Tool for OCP

Usage: update_ocp.sh [options]

with options:

   --skip-pull-secret         Skip the creation of the pull-secret. By default, will create or replace the pull-secret.
   --version                  Print target version to update to and exit.
-v --verbose                  Verbose logging
EOT
}

# ============================================================

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

# ==============================================================

waiting_api_error_is_gone() {
  set +e
  output=$(oc get syndesis 2>&1 > /dev/null)
  if [[ $output == *"Error from server (NotFound): Unable to list"* ]]; then
    echo "Waiting (up to 10 minutes) until 'oc get syndesis' command recognize a new Syndesis api version (ENTESB-17668)"
    i=0
    while [[ $(oc get syndesis 2>&1 > /dev/null) == *"Error from server (NotFound): Unable to list"* ]];
    do
      ((i=i+1))
      echo -ne "."
      sleep 10
      if [[ "$i" -gt 60 ]]; then
        echo -ne '\n'
        echo "ERROR: 'oc get syndesis' command is still not working properly after 10 minutes. See the error which it returns for more info!"
        exit 1
      fi
    done
    echo -ne '\n'
  fi
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

# ==================================================================

if [ $(hasflag --version) ]; then
    echo "Update to Fuse Online $TAG"
    echo
    echo "syndesis-operator:  ${SYNDESIS_VERSION}"
    exit 0
fi

# Check for OC
setup_oc

# Workaround for ENTESB-17668
waiting_api_error_is_gone

# Check whether there is an installation
check_error "$(check_syndesis)"


# make sure pull secret is present, only required from
if [ ! $(hasflag --skip-pull-secret) ]; then
  create_or_replace_secret
fi

# Update syndesis operator
echo "Update Syndesis operator"
$SYNDESIS_CLI install operator

oc scale deployment syndesis-operator --replicas 0
result=$(oc secrets link syndesis-operator syndesis-pull-secret --for=pull >$ERROR_FILE 2>&1)
check_error $result
if [ $(is_ocp3) == "true" ]; then
   oc set env deployment/syndesis-operator RELATED_IMAGE_PROMETHEUS='registry.redhat.io/openshift3/prometheus:v3.9'
fi
oc scale deployment syndesis-operator --replicas 1

jaeger_enabled=$(oc get syndesis app -o jsonpath='{.spec.addons.jaeger.enabled}')
check_error $jaeger_enabled
if [ "$jaeger_enabled" == "true" ]; then
    # on OCP 4 the jaeger-operator is installed from operatorhub on openshift-operator namespace
    # in that case there is no need to set secrets for it
    if [ $(is_ocp3) == "true" ]; then
        # we need to wait till the update process is started and the previous jaeger-operator SA is deleted ENTESB-15363
        echo "Waiting till jaeger-operator service account will be deleted and created again (ENTESB-15363)"
        wait_for_resource_is_deleted sa jaeger-operator
        
        wait_for sa jaeger-operator
        result=$(oc secrets link jaeger-operator syndesis-pull-secret --for=pull)
        check_error $result
        # workaround as the previous "oc secrets link" doesn't trigger a pod restart
        oc delete `oc get -o name pod -l name=jaeger-operator`
       
        wait_for sa syndesis-jaeger-ui-proxy
        result=$(oc secrets link syndesis-jaeger-ui-proxy syndesis-pull-secret --for=pull)
        check_error $result
        # workaround as the previous "oc secrets link" doesn't trigger a pod restart
        oc delete `oc get -o name pod -l app.kubernetes.io/name=syndesis-jaeger`
    fi


fi

# Workaround for ENTESB-17354
if [ $(is_ocp3) == "true" ]; then
   oc patch syndesises/app --type=merge -p '{"status":{"forceUpgrade": "false"}}'
fi


cat <<EOT
========================================================
Fuse Online operator has been updated to $TAG !
Please wait for the upgrade process to be finished by the operator.
EOT
