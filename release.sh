#!/bin/bash

# Save global script args
ARGS=("$@")



# Exit if any error occurs
# Fail on a single failed command in a pipeline (if supported)
set -o pipefail

# Fail on error and undefined vars (please don't use global vars, but evaluation of functions for return values)
set -eu


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
        if [ -n "$moving_tag" ]; then
            echo "* Pushing symbolic tag $moving_tag"
            git push -f -u $remote $moving_tag
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

extract_minor_version() {
    local version=$1
    local minor_version=$(echo $version | sed 's/^\([0-9]*\.[0-9]*\)\.[0-9]*\(-.*\)*$/\1/')
    if [ "$minor_version" = "$version" ]; then
        echo "ERROR: Cannot extract minor version from $version"
        return
    fi
    echo $minor_version
}

create_templates() {
    local topdir=$1
    local syndesis_git_tag=$2
    local fuse_ignite_tag=$3

    local tempdir=$(mktemp -d)
    trap "rm -rf \"${tempdir}\"" EXIT

    # Check out git first
    pushd $tempdir
    echo "==== Cloning syndesisio/syndesis, $syndesis_git_tag"
    git clone https://github.com/syndesisio/syndesis.git
    cd syndesis
    git co $syndesis_git_tag

    cd install/generator

    local is_tag
    if [ "$fuse_ignite_tag" = "master" ]; then
        is_tag="latest"
    else
        is_tag=$(extract_minor_version $fuse_ignite_tag)
    fi

    echo "==== Creating OSO product template for $is_tag"
    sh run.sh --name fuse-ignite --oso --syndesis-tag=${is_tag}
    cp ../syndesis.yml "$topdir/resources/fuse-ignite-oso.yml"

    echo "==== Creating OCP product template for $is_tag"
    sh run.sh --name fuse-ignite --ocp --syndesis-tag=${is_tag}
    cp ../syndesis.yml "$topdir/resources/fuse-ignite-ocp.yml"

    echo "==== Copy support SA"
    cp ../support/serviceaccount-as-oauthclient-restricted.yml \
       "$topdir/resources/serviceaccount-as-oauthclient-restricted.yml"

    echo "==== Patch install script with tag"
    sed -e "s/^TAG=.*\$/TAG=$fuse_ignite_tag/" -i "" $topdir/install_ocp.sh

    echo "==== Patch imagestream script with current versions"
    local brew_tag=$(readopt --version-brew)
    sed -e "s/{{[ ]*Tags.Ignite[ ]*}}/$is_tag/g" \
        -e "s/{{[ ]*Tags.Brew[ ]*}}/$brew_tag/g" \
        $topdir/templates/fuse-ignite-image-streams.yml \
        > $topdir/resources/fuse-ignite-image-streams.yml

    popd
}

# Left over from 'syndesis release'
release() {
    local topdir=$1
    local syndesis_tag=$2
    local fuse_ignite_tag=$3

    create_templates $topdir $syndesis_tag $fuse_ignite_tag

    echo "==== Committing"
    cd $topdir
    git_commit "releases/" "Update OpenShift templates and install script for Syndesis upstream $syndesis_tag" "$fuse_ignite_tag"
    git_commit "install_ocp.sh" "Update OpenShift templates and install script for Syndesis upstream $syndesis_tag" "$fuse_ignite_tag"

    # No tagging when just running on master
    if [ $fuse_ignite_tag = "master" ]; then
        return
    fi

    echo "=== Tagging $fuse_ignite_tag"
    git tag -f "${fuse_ignite_tag}"

    local moving_tag=$(extract_minor_version $fuse_ignite_tag)
    check_error $moving_tag

    echo "=== Moving tag $moving_tag"
    git tag -f "${moving_tag}"

    # Push release tag only
    git_push "$topdir" "$fuse_ignite_tag" "$moving_tag"
}


# ==========================================================================================

if [ $(hasflag --verbose) ]; then
    export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -x
fi

syndesis_tag=$(readopt --version-syndesis)
if [ -z "${syndesis_tag}" ]; then
    echo "ERROR: No version given with --version-syndesis"
    exit 1
fi

if [ -z "$(readopt --version-brew)" ]; then
    echo "ERROR: The brew version for the imagestreams needs to be specified"
    exit 1
fi

fuse_ignite_tag=$(readopt --version-fuse-ignite)
if [ -z "${fuse_ignite_tag}" ]; then
    fuse_ignite_tag="${syndesis_tag}"
fi
release "$(basedir)" $syndesis_tag $fuse_ignite_tag
