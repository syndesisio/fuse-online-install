#!/bin/bash
#
# Common openshift functions for install scripts

source "$BASEDIR/common_config.sh"

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

wait_for_deployments() {
  local res_type=$1
  local replicas_desired=$2
  shift
  shift
  local dcs="$@"

  oc get pods -w &
  watch_pid=$!
  for dc in $dcs; do
      echo "Waiting for $dc to be scaled to ${replicas_desired}"
      local replicas=$(get_replicas $dc $res_type)
      while [ -z "$replicas" ] || [ "$replicas" -ne $replicas_desired ]; do
          echo "Sleeping 10s ..."
          sleep 10
          replicas=$(get_replicas $dc $res_type)
      done
  done
  kill $watch_pid
}

# wait for a resource. Ex: wait_for sa syndesis-operator
wait_for() {
  local res_type=$1
  local resource=$2

  local resource_ready=$(check_resource $res_type $resource)
  while [ $resource_ready == "false" ]; do
      resource_ready=$(check_resource $res_type $resource)
      if [ $resource_ready == "false" ]; then
        sleep 4
      fi
  done
}

wait_for_resource_is_deleted() {
  local res_type=$1
  local resource=$2

  local resource_ready=$(check_resource $res_type $resource)
  while [ $resource_ready == "true" ]; do
      resource_ready=$(check_resource $res_type $resource)
      if [ $resource_ready == "true" ]; then
        sleep 4
      fi
  done
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

get_replicas() {
  local name=${1}
  local res_type=$2
  local hasDc=$(oc get $res_type -o name | grep $name)
  if [ -z "$hasDc" ]; then
      echo "0"
      return
  fi
  oc get $res_type $name -o jsonpath="{.status.availableReplicas}"
}

check_oc_version()
{
    local minimum=${OC_MIN_VERSION}
    #
    # Removes any lines containing kubernetes or server
    # Extracts any version number of the format dd.dd.dd, eg. 3.10.0 or 4.1.0
    #
    local test=$(oc version | grep -Eiv 'kubernetes|server' | grep -o '[0-9]\{1,\}\.[0-9]\{1,\}\.[0-9]\{1,\}\?')

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
      mini_running=$(minishift oc-env|grep -c PATH)
      if [[ ${mini_running} == 1 ]]; then
        eval $(minishift oc-env)
        err=$(check_oc_version)
        check_error $err
        return
      fi
    fi
    if [[ -d $HOME/.minishift ]]; then
      oc_bin=$(find $HOME/.minishift/ -name oc -type f | sort | tail -1)
      if [ -n "$oc_bin" ]; then
        oc_dir=$(dirname $oc_bin)
        export PATH=$PATH:$oc_dir
        return
      fi
    fi

    set -e

    # Error, no oc found
    echo "ERROR: No 'oc' binary found in path. Please install the client tools from https://github.com/openshift/origin/releases/tag/v${OC_MIN_VERSION} (or newer)"
    return
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

# ==================================================================

# Check whether syndesis-pull-secret secret is present and create
# it otherwise
#
create_or_replace_secret() {
  if $(check_resource secret syndesis-pull-secret) ; then
    echo "Removing syndesis-pull-secret & replacing with updated version ..."
    local result=$(oc delete secret syndesis-pull-secret)
    check_error $result
  fi

  #
  # Test the credentials entered and give a couple of subsequent tries
  # then exit if still not right
  #
  iterations=0
  max=2
  while [  $iterations -le $max ];
  do
    echo "creating pull secret 'syndesis-pull-secret' ..."
    echo "enter username for redhat registry access and press [ENTER]: "
    read username
    echo "enter password for redhat registry access and press [ENTER]: "
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

  set +e

  #
  # Need to ensure there are no extra carriage returns
  #
  local auth=$(printf "%s:%s" "${username}" "${password}" | base64 -w 0)

  #
  # Encode the whole pull secret for both registries
  #
  local pull_secret=$(base64 -w 0 <<EOF
{
  "auths": {
    "registry.redhat.io": {
      "auth":"${auth}"
    },
    "registry.connect.redhat.com": {
      "auth":"${auth}"
    }
  }
}
EOF
)

  #
  # Create the new secret on the cluster
  #
  local result=$(oc create -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: syndesis-pull-secret
data:
  .dockerconfigjson: ${pull_secret}
type: kubernetes.io/dockerconfigjson
EOF
)

  check_error $result
  set -e
}

#
# Checks whether the current user is a cluster admin
#
is_cluster_admin() {
  oc get clusterrolebindings > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "ERROR: Cannot execute as current user is not a cluster-admin."
    return
  fi

  echo "OK"
}

#
# Checks where the syndesis-installer role has been grant to the project
#
is_role_granted() {
  local user=$(oc whoami)

  oc get rolebinding syndesis-installer-${user} > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    # Have a role binding for this user so return
    echo "OK"
    return
  fi

  oc get clusterrolebinding syndesis-installer-${user} > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    # Have a cluster role binding for this user so return
    echo "OK"
    return
  fi

  echo "ERROR: The user '${user}' does not have the 'syndesis-installer' role. Please execute '... --grant' as a cluster-admin first."
}

is_ocp3() {
    # oc version outputs the kubernetes version
    # openshift 3.11 supports kubernetes 1.11.0
    # openshift 4.x starts with kubernetes 1.13
    # output is:
    #   ocp 4.6  Kubernetes Version: v1.19.0+d59ce34
    #   ocp 3.11 kubernetes v1.11.0+d4cacc0
    local version=$(oc version|tail -1|awk -F 'v1.' '{print $2}'|awk -F '.' '{print $1}')
    if [ -z $version ]; then
        echo "ERROR: Unable to detect kubernetes version with 'oc version'"
    fi
    if [ $version -gt 12 ]; then
        echo "false"
    else
        echo "true"
    fi
}
