#!/bin/bash

# Save global script args
ARGS=("$@")

# Exit if any error occurs
# Fail on a single failed command in a pipeline (if supported)
set -o pipefail

# Fail on error and undefined vars (please don't use global vars, but evaluation of functions for return values)
set -eu

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
    for var in "${ARGS[@]:-}"; do
        for filter in $filters; do
          if [ "$var" = "$filter" ]; then
              echo 'true'
              return
          fi
        done
    done
}

# Read the value of an option.
readopt() {
    filters="$@"
    next=false
    for var in "${ARGS[@]:-}"; do
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
}

# Getting base dir
BASEDIR=$(basedir)

# Get configuration and other scripts
pushd > /dev/null . && cd $BASEDIR
source $BASEDIR/base_functions.sh
source $BASEDIR/common_config.sh
source $BASEDIR/libs/download_functions.sh
source $BASEDIR/libs/openshift_functions.sh
source $BASEDIR/libs/docker_functions.sh
popd > /dev/null


display_usage() {
  cat <<EOT
Release tool for fuse-online

Usage: bash release.sh [options]

with options:

--help                       This help message
--git-push                   Push to git directly
--move-tag                   Create the moving tag
--dry-run -n                 Dry run
--git-remote                 Push to a different git remote
--skip-binary-release        Ignore release of binary artifacts
--skip-template-release      Ignore release of template artifact (deprecated)
--verbose                    Verbose log output

Please check also "common_config.sh" for the configuration values.
EOT
}



git_commit() {
    local pattern="$1"
    local message="$2"
    local release_version="$3"

    if [ ! $(hasflag --dry-run -n) ]; then
        local mod_files=$(git diff --cached --name-only | grep $pattern)
        if [ -n "$mod_files" ]; then
            echo "$mod_files" | xargs git commit -m "[$release_version]: $message"
        else
            echo "Nothing changed"
        fi
    fi
}

git_push() {
    local topdir=${1:-}
    local release_version=${2:-}
    local moving_tag=${3:-}

    cd $topdir

    if [ $(hasflag --git-push) ]; then
        local remote=$(readopt --git-remote)
        if [ -z "${remote}" ]; then
            # Push to the remote attached to the local checkout branch
            remote=$(git for-each-ref --format='%(upstream:short)' $(git symbolic-ref -q HEAD) | sed -e 's/\([^\/]*\)\/.*/\1/')
            if [ -z "${remote}" ]; then
              echo "ERROR: Cannot find remote repository to git push to"
              exit 1
            fi
        fi

        echo "==== Pushing to GitHub"
        if [ -n "$release_version" ]; then
            echo "* Pushing $release_version"
            git push -u $remote $release_version
        fi

        if [ $(hasflag --move-tag) ]; then
            if [ -n "$moving_tag" ]; then
                echo "* Pushing symbolic tag $moving_tag"
                git push -f -u $remote $moving_tag
            fi
        fi
    fi
}

get_github_username() {
    if [ -z "${GITHUB_USERNAME:-}" ]; then
        echo "ERROR: environment variable GITHUB_USERNAME has not been set."
        echo "Please populate it with your github id"
        return
    fi
    echo $GITHUB_USERNAME
}

get_github_access_token() {
    if [ -z "${GITHUB_ACCESS_TOKEN:-}" ]; then
        echo "ERROR: environment variable GITHUB_ACCESS_TOKEN has not been set."
        echo "Please populate it with a valid personal access token from github (with 'repo', 'admin:org_hook' and 'admin:repo_hook' scopes)."
        return
    fi
    echo $GITHUB_ACCESS_TOKEN
}

publish_artifacts() {
    local release_dir=$1

    set +e
    local upload_url=$(curl -q --fail -X POST -u $GITHUB_USERNAME:${GITHUB_ACCESS_TOKEN} -H "Accept: application/vnd.github.v3+json" -H "Content-Type: application/json" -d "{\"tag_name\": \"$BIN_TAG_PREFIX$TAG_FUSE_ONLINE_INSTALL\"}" https://api.github.com/repos/${COMMON_RELEASE_GIT_ORG}/${COMMON_RELEASE_GIT_REPO}/releases | jq -r .upload_url | cut -d{ -f1)
    if [[ ! $upload_url == http* ]]; then
        echo "ERROR: Cannot create release on remote github repository. Check if a release with the same tag already exists."
        return
    fi
    set -e

    set +e
    for file in $release_dir/*; do
        curl -q --fail -X POST -u $GITHUB_USERNAME:$GITHUB_ACCESS_TOKEN \
          -H "Accept: application/vnd.github.v3+json" \
          -H "Content-Type: application/tar+gzip" \
          --data-binary "@$file" \
          $upload_url?name=${file##*/} >$ERROR_FILE 2>&1
        local err=$?
        set -e
        if [ $err -ne 0 ]; then
          echo "ERROR: Cannot upload release artifact $file on remote github repository"
          return
        fi
    done
}

release_binaries() {
    if [ $(hasflag --skip-binary-release) ]; then
        echo "Skipping release of binary artifacts"
        return
    fi

    local release_dir=$(extract_binaries)
    check_error $release_dir

    if [ ! $(hasflag --dry-run -n) ]; then
        local github_username=$(get_github_username)
        check_error $github_username

        local github_token=$(get_github_access_token)
        check_error $github_token

        result=$(publish_artifacts $release_dir)
        check_error $result
    fi
}

extract_binaries() {
    local tmp_dir=/tmp/fuse-online-clients
    rm -rf $tmp_dir
    mkdir -p $tmp_dir
    chmod a+rw $tmp_dir

    local release_dir=$tmp_dir/release
    mkdir -p $release_dir

    local syndesis_dir=$tmp_dir/syndesis
    mkdir -p $syndesis_dir
    result=$(extract_from_docker $SYNDESIS_IMAGE /opt/clients/* $syndesis_dir)
    check_error $result

    local camel_k_dir=$tmp_dir/camel_k
    mkdir -p $camel_k_dir
    result=$(extract_from_docker $CAMEL_K_IMAGE /opt/clients/* $camel_k_dir)
    check_error $result

    set +e
    pushd > /dev/null . && cd $syndesis_dir/darwin-amd64 && gunzip syndesis-operator.gz && \
      tar czvf $release_dir/syndesis-${SYNDESIS_VERSION}-mac-64bit.tar.gz syndesis-operator > /dev/null 2>&1 && \
      popd > /dev/null
    local err=$?
    set -e
    if [ $err -ne 0 ]; then
      echo "ERROR: Cannot extract syndesis client binaries for mac"
      return
    fi

    set +e
    pushd > /dev/null . && cd $syndesis_dir/windows-amd64 && gunzip syndesis-operator.gz && \
      mv syndesis-operator syndesis-operator.exe && \
      tar czvf $release_dir/syndesis-${SYNDESIS_VERSION}-windows-64bit.tar.gz syndesis-operator.exe > /dev/null 2>&1 && \
      popd > /dev/null
    local err=$?
    set -e
    if [ $err -ne 0 ]; then
      echo "ERROR: Cannot extract syndesis client binaries for windows"
      return
    fi

    set +e
    pushd > /dev/null . && cd $syndesis_dir/linux-amd64 && \
      tar czvf $release_dir/syndesis-${SYNDESIS_VERSION}-linux-64bit.tar.gz syndesis-operator > /dev/null 2>&1 \
      && popd > /dev/null
    local err=$?
    set -e
    if [ $err -ne 0 ]; then
      echo "ERROR: Cannot extract syndesis client binaries for linux"
      return
    fi

    set +e
    mv $camel_k_dir/camel-k-client-linux.tar.gz $release_dir/camel-k-client-${CAMEL_K_VERSION}-linux-64bit.tar.gz && \
      mv $camel_k_dir/camel-k-client-mac.tar.gz $release_dir/camel-k-client-${CAMEL_K_VERSION}-mac-64bit.tar.gz && \
      mv $camel_k_dir/camel-k-client-windows.tar.gz $release_dir/camel-k-client-${CAMEL_K_VERSION}-windows-64bit.tar.gz
    local err=$?
    set -e
    if [ $err -ne 0 ]; then
      echo "ERROR: Cannot extract camel-k client binaries"
      return
    fi

    echo $release_dir
}

release_template() {
    if [ $(hasflag --skip-template-release) ]; then
        echo "Skipping release of template artifact"
        return
    fi

    local release_dir="$topdir/templates"

    #
    # docker uses the 'darwin' directory rather than mac
    #
    osdir=${CURRENT_OS}
    if [ "$osdir" == "mac" ]; then
      osdir="darwin"
    fi

    local tmp_dir="$(mktemp -d /tmp/fuse-template-XXXXX)"
    chmod a+rw $tmp_dir

    local syndesis_dir=$tmp_dir/syndesis
    mkdir -p $syndesis_dir
    # Fetch the syndesis operator appropriate to this platform & its config file
    result=$(extract_from_docker $SYNDESIS_IMAGE "/opt/clients/$osdir*/*operator*;/conf/config.yaml" $syndesis_dir)
    check_error $result

    set +e
    SYNDESIS_BINARY="syndesis-operator"
    pushd $syndesis_dir > /dev/null
    if [ -f "${SYNDESIS_BINARY}.gz" ]; then
        if [ $osdir == "windows" ]; then
          gunzip "${SYNDESIS_BINARY}.gz" && mv ${SYNDESIS_BINARY} ${SYNDESIS_BINARY}.exe
          SYNDESIS_BINARY="${SYNDESIS_BINARY}.exe"
        else
          gunzip "${SYNDESIS_BINARY}.gz"
        fi
    fi
    set -e

    if [ ! -x $SYNDESIS_BINARY ]; then
        echo "ERROR: Cannot find syndesis-operator binary to generate template"
        return
    fi

    #
    # Execute the syndesis-operator to generate the template
    #
    local FUSE_TEMPLATE="fuse-online-template.yml"

    set +e
    "./$SYNDESIS_BINARY" install forge --operator-config config.yaml --addons todo,dv > $FUSE_TEMPLATE
     local err=$?
    set -e
    if [ $err -ne 0 ]; then
      echo "ERROR: Cannot generate template from syndesis-operator"
      return
    fi

    #
    # Need to remove the deploymentconfigs/finalizers permission from template since the user installing the template
    # on some systems does not normally have this permission.
    # This will cause issues, as documented in ENTESB-11639, but that's a short-term balance to be struck.
    #
    sed -i '/deploymentconfigs\/finalizers/d' $FUSE_TEMPLATE

    mkdir -p $release_dir
    mv $FUSE_TEMPLATE $release_dir/
    popd > /dev/null

    if [ ! -f "$release_dir/$FUSE_TEMPLATE" ]; then
        echo "ERROR: Template failed to be generated"
        return
    fi

    git add $release_dir/$FUSE_TEMPLATE
    git_commit "$FUSE_TEMPLATE" "Update release template for $TAG_FUSE_ONLINE_INSTALL" "$TAG_FUSE_ONLINE_INSTALL"
    rm -rf $tmp_dir
}

check_error() {
    local msg="$*"
    if [ "${msg//ERROR/}" != "${msg}" ]; then
        echo $msg
        exit 1
    fi
}

release() {
    local topdir=$1

    echo "==== Releasing binary files"
    release_binaries

    echo "==== Releasing template file"
    release_template

    echo "==== Committing"
    cd $topdir
    git add common_config.sh
    git_commit "common_config.sh" "Update release config for $TAG_FUSE_ONLINE_INSTALL" "$TAG_FUSE_ONLINE_INSTALL"

    # No tagging when just running on master
    if [ $TAG_FUSE_ONLINE_INSTALL = "master" ]; then
        return
    fi

    echo "=== Tagging $TAG_FUSE_ONLINE_INSTALL"
    git tag -f "$TAG_FUSE_ONLINE_INSTALL"

    local moving_tag=$TAG

    if [ $(hasflag --move-tag) ]; then
        echo "=== Moving tag $TAG"
        git tag -f "$TAG"
    fi

    # Push release tag only
    git_push "$topdir" "$TAG_FUSE_ONLINE_INSTALL" "$TAG"
}


# ==========================================================================================

if [ $(hasflag --help -h) ]; then
    display_usage
    exit 0
fi

if [ $(hasflag --verbose) ]; then
    export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -x
fi

release "$(basedir)"
