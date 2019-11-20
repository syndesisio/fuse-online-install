#!/bin/bash

# ====================================================
# Standalone script for deploying syndesis on OCP (including imagestreams)
# It is based on https://github.com/syndesisio/syndesis/blob/master/tools/bin/install-syndesis
# except that the TAG is frozen during the release

# ================
# Tag updated by release script
TAG=1.7.20
# ================

# Minimal version for OC
OC_MIN_VERSION=3.9.0

# Exit if any error occurs
# Fail on a single failed command in a pipeline (if supported)
set -o pipefail

# Fail on error and undefined vars (please don't use global vars, but evaluation of functions for return values)
set -eu

# Save global script args
ARGS=("$@")


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
   --camel-k <version>        Install camel-k operator version <version>
                              (version is optional)
   --camel-k-options "opts"   Options used when installing the camel-k operator.
                              Use quotes and start with a space before appending the options.
   --datavirt                 Install Data Virtualizations.
   --help                     This help message
-v --verbose                  Verbose logging

You have to run `--setup --grant <user>` as a cluster-admin before you can install Fuse Online as a user.
EOT
}

# ============================================================
# Helper functions taken over from "syndesis" CLI:

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

# Install the Syndesis custom resource definition
install_syndesis_crd() {
    set +e
    oc get crd >/dev/null 2>&1
    local err=$?
    set -e
    if [ $err -ne 0 ]; then
        echo "ERROR: Cannot install CRD 'Syndesis'. You have to be a cluster admin to do this."
        return
    fi

    local crd_installed=$(oc get crd -o name | grep syndesises.syndesis.io)
    if [ -z "$crd_installed" ]; then
        local result=$(create_openshift_resource "resources/syndesis-crd.yml")
        check_error $result
    fi
}

add_user_permissions_for_operator() {
    local user="$1"
    local cluster_wide=${2:-false}

    if [ -z "$user" ]; then
        echo "ERROR: No user provided to fix permissions for"
        return
    fi
    local kind="Role"
    local oc_command="policy add-role-to-user --role-namespace=$(oc project -q)"
    if $cluster_wide; then
        kind="ClusterRole"
        oc_command="adm policy add-cluster-role-to-user"
    fi

    set +e
    oc replace --force -f - >/dev/null 2>&1 <<EOT
---
kind: $kind
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: syndesis-extra-permissions
  labels:
    app: syndesis
    syndesis.io/app: syndesis
    syndesis.io/type: operator
    syndesis.io/component: syndesis-operator
rules:
- apiGroups:
  - syndesis.io
  resources:
  - "*"
  - "*/finalizers"
  verbs: [ get, list, create, update, delete, deletecollection, watch ]
- apiGroups:
  - ""
  resources:
  - pods
  - services
  - endpoints
  - persistentvolumeclaims
  - configmaps
  - secrets
  - serviceaccounts
  verbs: [ get, list, create, update, delete, deletecollection, watch ]
- apiGroups:
  - extensions
  resources:
  - deployments/rollback
  verbs: [ get, list, create, update, delete, deletecollection, watch, patch ]
- apiGroups:
  - ""
  resources:
  - pods/log
  verbs: [ get ]
- apiGroups:
  - ""
  resources:
  - replicationcontrollers
  - replicationcontrollers/scale
  - replicationcontrollers/status
  verbs: [ get, list, create, update, delete, deletecollection, watch ]
- apiGroups:
  - ""
  - build.openshift.io
  resources:
  - builds
  - buildconfigs
  - builds/details
  - buildconfigs/webhooks
  - buildconfigs/instantiatebinary
  - builds/log
  verbs: [ get, list, create, update, delete, deletecollection, watch ]
- apiGroups:
  - ""
  - apps.openshift.io
  resources:
  - deploymentconfigs
  - deploymentconfigs/scale
  verbs: [ get, list, create, update, delete, deletecollection, watch, patch ]
- apiGroups:
  - ""
  - apps.openshift.io
  resources:
  - deploymentconfigrollbacks
  - deploymentconfigs/instantiate
  - deploymentconfigs/rollback
  verbs: [ create ]
- apiGroups:
  - ""
  - apps.openshift.io
  resources:
  - deploymentconfigs/log
  - deploymentconfigs/status
  verbs: [ get, list, watch ]
- apiGroups:
  - ""
  - image.openshift.io
  resources:
  - imagestreams
  - imagestreamimages
  - imagestreammappings
  - imagestreams/secrets
  - imagestreamtags
  verbs: [ get, list, create, update, delete, deletecollection, watch, patch ]
- apiGroups:
  - ""
  - image.openshift.io
  resources:
  - imagestreams/status
  - imagestreamimports
  verbs: [ get, list, watch ]
- apiGroups:
  - ""
  resources:
  - events
  verbs: [ get, list ]
- apiGroups:
  - rbac.authorization.k8s.io
  resources:
  - roles
  - rolebindings
  verbs: [ get, list, create, update, delete, deletecollection, watch ]
- apiGroups:
  - ""
  - template.openshift.io
  resources:
  - processedtemplates
  - templateconfigs
  - templateinstances
  - templates
  verbs: [ get, list, create, update, delete, deletecollection, watch, patch ]
- apiGroups:
  - authorization.openshift.io
  resources:
  - rolebindings
  verbs: [ get, list, create, update, delete, deletecollection, watch ]
- apiGroups:
  - route.openshift.io
  resources:
  - routes
  - routes/custom-host
  verbs: [ get, list, create, update, delete, deletecollection, watch, patch ]
- apiGroups:
  - camel.apache.org
  resources:
  - "*"
  verbs: [ get, list, create, update, delete, deletecollection, watch ]
- apiGroups:
  - monitoring.coreos.com
  resources:
  - alertmanagers
  - prometheuses
  - servicemonitors
  - prometheusrules
  verbs: [ get, list, create, update, delete, deletecollection, watch ]
- apiGroups:
  - integreatly.org
  resources:
  - grafanadashboards
  verbs: [ get, list, create, update, delete, deletecollection, watch ]
- apiGroups:
  - serving.knative.dev
  resources:
  - services
  verbs: [ get, list, watch ]
- apiGroups:
  - eventing.knative.dev
  resources:
  - channels
  verbs: [ get, list, watch ]
---

EOT
    if [ $? -ne 0 ]; then
        echo "ERROR: Can not install role 'syndesis-extra-permissions'. Are you running as cluster-admin ?"
        return
    fi

    oc $oc_command syndesis-extra-permissions "$user"
    if [ $? -ne 0 ]; then
        echo "ERROR: Can not add role 'syndesis-extra-permssions' to user $user. Does the user exist ?"
        return
    fi
    set -e
}

recreate_project() {
    local project=$1
    local dont_ask=${2:-false}

    if [ -z "$project" ]; then
        echo "No project given"
        exit 1
    fi

    # Delete project if existing
    if oc get project "${project}" >/dev/null 2>&1 ; then
        if [ $dont_ask != "true" ]; then
            echo =============== WARNING -- Going to delete project ${project}
            oc get all -n $project
            echo ============================================================
            read -p "Do you really want to delete the existing project $project ? yes/[no] : " choice
            echo
            if [ "$choice" != "yes" ] && [ "$choice" != "y" ]; then
                echo "Aborting on user's request"
                exit 1
            fi
        fi
        echo "Deleting project ${project}"
        oc delete project "${project}"
    fi

    # Create project afresh
    echo "Creating project ${project}"
    for i in {1..10}; do
        if oc new-project "${project}" >/dev/null 2>&1 ; then
            break
        fi
        echo "Project still exists. Sleeping 10s ..."
        sleep 10
    done
    oc project "${project}"
}

check_oc_version()
{
    local minimum=${OC_MIN_VERSION}
    local test=$(oc version | grep ^oc | tr -d oc\ v | cut -f1 -d "+")
    if [ "$test" = "" ]; then
        local test=$(oc version | grep 'Client Version' | sed "s/^.*GitVersion:\"v\(.*\)\", GitCommit.*$/\1/")
    fi

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

ensure_image_streams() {
    local is_installed=$(oc get imagestream -o name | grep fuse-ignite-server)
    if [ -n "$is_installed" ]; then
        local result=$(delete_openshift_resource "resources/fuse-online-image-streams.yml")
        check_error $result
    fi

    local result=$(create_openshift_resource "resources/fuse-online-image-streams.yml")
    check_error $result
}

# Deploy operator
deploy_syndesis_operator() {

    local operator_installed=$(oc get dc -o name | grep syndesis-operator)
    if [ -n "$operator_installed" ]; then
        local result=$(delete_openshift_resource "resources/fuse-online-operator.yml")
        check_error $result
        wait_for_deployments 0 syndesis-operator >/dev/null 2>&1
    fi

    create_openshift_resource "resources/fuse-online-operator.yml"

    local result=$(oc secrets link syndesis-operator syndesis-pull-secret --for=pull >$ERROR_FILE 2>&1)
    check_error $result

    #
    # Wait for & check the operator stream is functioning correctly
    #
    iterations=0
    while [  $iterations -lt 4 ];
    do
      sleep 3
      local result=$(oc describe is/fuse-online-operator 2>&1)
      if [ -z "${result##*error*}" ]; then
        printf "ERROR: Cannot deploy operator as image stream has an error: %s" "$result"
        return
      fi
      let iterations=iterations+1
    done
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
    #local url="./${resource}"
    result=$(oc $what -f $url >$ERROR_FILE 2>&1)
    if [ $? -ne 0 ]; then
        echo "ERROR: Cannot create remote resource $url"
    fi
    set -e
}

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

  openShiftConsoleUrl: "$console"
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

wait_for_deployments() {
  local replicas_desired=$1
  shift
  local dcs="$@"

  oc get pods -w &
  watch_pid=$!
  for dc in $dcs; do
      echo "Waiting for $dc to be scaled to ${replicas_desired}"
      local replicas=$(get_replicas $dc)
      while [ -z "$replicas" ] || [ "$replicas" -ne $replicas_desired ]; do
          echo "Sleeping 10s ..."
          sleep 10
          replicas=$(get_replicas $dc)
      done
  done
  kill $watch_pid
}

get_replicas() {
  local dc=${1}
  local hasDc=$(oc get dc -o name | grep $dc)
  if [ -z "$hasDc" ]; then
      echo "0"
      return
  fi
  oc get dc $dc -o jsonpath="{.status.availableReplicas}"
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

# ==================================================================

# Getting options from config file
eval $(source $(dirname ARGS[0])/fuse_online_config.sh; echo MAVEN_REPOSITORY=$maven_repository)
eval $(source $(dirname ARGS[0])/fuse_online_config.sh; echo CAMEL_K_TAG=$tag_camel_k)
eval $(source $(dirname ARGS[0])/fuse_online_config.sh; echo REPOSITORY=$repository_tech_preview)
eval $(source $(dirname ARGS[0])/fuse_online_config.sh; echo FUSE_JAVA_REPOSITORY=$repository)
eval $(source $(dirname ARGS[0])/fuse_online_config.sh; echo REGISTRY=$registry)
eval $(source $(dirname ARGS[0])/fuse_online_config.sh; echo JAVA_BASE_IMAGE_TAG=$tag_java_base_image)

# Deploy Camel-K operator
deploy_camel_k_operator() {
  local version=${1:-}
  local project=${2:-}
  local opts=${3:-}
  local extra_opts=""
  if [ -n "$project" ]; then
    extra_opts="--namespace $project"
  fi
  if [ -n "$opts" ]; then
    extra_opts="$extra_opts $opts"
  fi
  local kamel=$(get_camel_k_bin "$version")
  if [ "${kamel//ERROR/}" != "${kamel}" ]; then
    echo $kamel
    return
  fi

  $kamel install --skip-cluster-setup --maven-repository $MAVEN_REPOSITORY --base-image $REGISTRY/$FUSE_JAVA_REPOSITORY/fuse-java-openshift:$JAVA_BASE_IMAGE_TAG --context jvm $extra_opts

  if [ -z "$version" ]; then
    # Patching Camel K image
    oc patch deployment camel-k-operator --type='json' -p="[{\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/image\", \"value\":\"$REGISTRY/$REPOSITORY/fuse-camel-k:$CAMEL_K_TAG\"}]"
  fi

  local result=$(oc secrets link camel-k-operator syndesis-pull-secret --for=pull >$ERROR_FILE 2>&1)
  check_error $result
}

# Install Camel-K CRD
install_camel_k_crds() {
  local version=${1:-}
  local kamel=$(get_camel_k_bin "$version")
  if [ "${kamel//ERROR/}" != "${kamel}" ]; then
    echo $kamel
    return
  fi

  $kamel install --cluster-setup
}

isMacOs() {
    if [ -z "${OSTYPE}" ]; then
        if [ $(uname) == "Darwin" ]; then
            echo "true"
        fi
    elif [ "${OSTYPE#darwin}" != "${OSTYPE}" ]; then
        echo "true"
    else
        echo "false"
    fi
}

isWindows() {
    if [ -z "${OSTYPE}" ]; then
        if [ $(uname) == "Windows" ]; then
            echo "true"
        fi
    elif [ "${OSTYPE#windows}" != "${OSTYPE}" ]; then
        echo "true"
    else
        echo "false"
    fi
}

get_camel_k_bin() {
    local version=${1:-}
    if [ -n "$version" ]; then
        get_upstream_camel_k_bin "$version"
    else
        get_product_camel_k_bin
    fi
}

# Download upstream `kamel` cli
# Currently it just download from GitHub
get_upstream_camel_k_bin() {
  local version=${1}
  local bin_dir=${2:-/tmp}

  local kamel_command="$bin_dir/kamel-${version}"
  if [ -e $kamel_command ]; then
    echo $kamel_command
    return
  fi

  # Check for proper operating system
  local os="linux"
  if $(isMacOs); then
    os="mac"
  elif $(isWindows); then
    os="windows"
  fi

  local download_url="https://github.com/apache/camel-k/releases/download/$version/camel-k-client-$version-$os-64bit.tar.gz"
  local archive=$(mktemp $bin_dir/camel-k-${version}.tar-XXXX)
  # Download from Camel-K site
  curl -sL -o $archive $download_url
  local tmp_dir=$(mktemp -d $bin_dir/camel-k-${version}-XXXX)
  pushd $tmp_dir >/dev/null
  tar xf $archive
  mv ./kamel $kamel_command
  popd >/dev/null
  [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ] && rm -rf $tmp_dir
  echo $kamel_command
}

# Get productized `kamel` cli
get_product_camel_k_bin() {
  local bin_dir=${2:-/tmp}
  local tmp_dir=${bin_dir}/fuse-online-tmp-camel-k-client
  mkdir -p $tmp_dir
  chmod a+rw $tmp_dir

  local image=$REGISTRY/$REPOSITORY/fuse-camel-k:$CAMEL_K_TAG

  set +e
  docker pull $image >$ERROR_FILE 2>&1
  local err=$?
  set -e
  if [ $err -ne 0 ]; then
      echo "ERROR: Cannot pull image $image."
      return
  fi

  local image_sha=$(docker inspect $image --format='{{index .RepoDigests 0}}' | sed 's/.*\://')

  local kamel_command="$bin_dir/kamel-prod-$image_sha"
  if [ -e $kamel_command ]; then
    echo $kamel_command
    return
  fi

  # Check for proper operating system
  local os="linux"
  if $(isMacOs); then
    os="mac"
  elif $(isWindows); then
    os="windows"
  fi

  set +e
  docker run -v $tmp_dir/:/client:z \
                 --entrypoint bash \
                 $REGISTRY/$REPOSITORY/fuse-camel-k:$CAMEL_K_TAG\
                 -c "tar xf /opt/clients/camel-k-client-$os.tar.gz; cp kamel /client/" >$ERROR_FILE 2>&1
  local err=$?
  set -e
  if [ $err -ne 0 ]; then
      echo "ERROR: Cannot copy client binary from Camel K image."
      return
  fi

  mv -f $tmp_dir/kamel $kamel_command
  [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ] && rm -rf $tmp_dir
  echo $kamel_command
}

# Check if a resource exist in OCP
check_resource() {
  local kind=$1
  local name=$2
  oc get $kind $name -o name >/dev/null 2>&1
  if [ $? != 0 ]; then
    echo "false"
  else
    echo "true"
  fi
}

# Check whether syndesis-pull-secret secret is present and create
# it otherwise
#
create_secret_if_not_present() {
  if $(check_resource secret syndesis-pull-secret) ; then
    echo "pull secret 'syndesis-pull-secret' present, skipping creation ..."
  else

    #
    # Test the credentials entered and give a couple of subsequent tries
    # then exit if still not right
    #
    iterations=0
    max=2
    while [  $iterations -le $max ];
    do
      echo "pull secret 'syndesis-pull-secret' is missing, creating ..."
      echo "enter username for registry.redhat.io and press [ENTER]: "
      read username
      echo "enter password for registry.redhat.io and press [ENTER]: "
      read -s password

      # Testing access that credentials are correct
      local reply=$(curl -IsL -u ${username}:${password} "https://sso.redhat.com/auth/realms/rhcc/protocol/redhat-docker-v2/auth?service=docker-registry&client_id=curl&scope=repository:rhel:pull")

      # Does reply contain "200 OK".
      if [ -z "${reply##*200 OK*}" ]; then
        # All good so break out of loop & carry on ...
        break
      else
        # Credentials wrong ... give a couple more tries or exit
        echo "ERROR: Credentials cannot be verified with redhat registry."
        if [ $iterations -lt $max ]; then
          echo "Please try again ... ($((iterations+1))/$((max+1)))"
        else
          echo "Exiting ... ($((iterations+1))/$((max+1)))"
          exit 1
        fi
      fi

      let iterations=iterations+1
    done

    echo "enter email address for registry.redhat.io and press [ENTER]: "
    read email
    local result=$(oc create secret docker-registry syndesis-pull-secret --docker-server=registry.redhat.io --docker-username=$username --docker-password=$password --docker-email=$email)
    check_error $result
  fi
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

prep_only="false"
if [ $(hasflag -s --setup) ]; then
    echo "Installing Syndesis CRD"
    result=$(install_syndesis_crd)
    check_error "$result"
    if [ $(hasflag --camel-k) ]; then
      echo "Installing Camel-K CRDs"
      result=$(install_camel_k_crds "$(readopt --camel-k)")
      check_error "$result"
    fi
    prep_only="true"
fi

user_to_prepare="$(readopt -u --grant)"
if [ -n  "$user_to_prepare" ]; then
    echo "Grant permission to create Syndesis to user $user_to_prepare"
    result=$(add_user_permissions_for_operator "$user_to_prepare" $(hasflag --cluster))
    check_error "$result"
    prep_only="true"
fi

if $prep_only; then
    exit 0
fi

# If a project is given, create it new or recreate it
project=$(readopt --project -p)
if [ -n "${project}" ]; then
    recreate_project $project
else
    project=$(oc project -q)
fi

# ==================================================================
# make sure pull secret is present (required since 7.3)
#
# must go after -p so it does not get wiped out by deleting the project
#
create_secret_if_not_present

# ==================================================================

# Check for OC
setup_oc

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

echo "Ensuring imagestreams in $project"
ensure_image_streams

# Deploy operator and wait until its up
echo "Deploying Syndesis operator"
result=$(deploy_syndesis_operator)
check_error "$result"

if [ $(hasflag --camel-k) ]; then
    echo "Deploying Camel-K operator"
    result=$(deploy_camel_k_operator "$(readopt --camel-k)" "$(oc project -q)" "$(readopt --camel-k-options)")
    check_error "$result"
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
