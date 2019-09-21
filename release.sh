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
pushd . && cd $BASEDIR
source $BASEDIR/base_functions.sh
source $BASEDIR/common_config.sh
source $BASEDIR/libs/download_functions.sh
source $BASEDIR/libs/openshift_functions.sh
popd


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
--verbose                    Verbose log output

Please check also "common_config.sh" for the configuration values.
EOT
}



git_commit() {
    local pattern="$1"
    local message="$2"
    local release_version="$3"

    if [ ! $(hasflag --dry-run -n) ]; then
        local mod_files=$(git ls-files --modified | grep $pattern)
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

check_error() {
    local msg="$*"
    if [ "${msg//ERROR/}" != "${msg}" ]; then
        echo $msg
        exit 1
    fi
}

release() {
    local topdir=$1

    echo "==== Committing"
    cd $topdir
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
