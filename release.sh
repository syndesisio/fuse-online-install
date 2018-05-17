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
    local minor_version=$(echo $version | sed -E -n 's/([0-9]+\.[0-9]+).*/\1/p')
    if [ "$minor_version" = "$version" ]; then
        echo "ERROR: Cannot extract minor version from $version"
        return
    fi
    echo $minor_version
}

read_image_version() {
    local image=$1
    local brew_tag=$2
    local result=$(readopt --version-$1)
    if [ -z "$result" ]; then
        result=$brew_tag
    fi
    if [ -n "$result" ]; then
        echo $result
    else
        echo "ERROR: No version given for $image and no --version-brew specified"
    fi
}

create_templates() {
    local topdir=$1
    local syndesis_git_tag=$2
    local fuse_ignite_tag=$3
    local docker_registry=$4
    local docker_image_repository=$5
    local maven_redhat_repository=$6
    local maven_jboss_repository=$7

    local tempdir=$(mktemp -d)
    trap "rm -rf \"${tempdir}\"" EXIT

    # Check out git first
    pushd $tempdir
    echo "==== Cloning syndesisio/syndesis, $syndesis_git_tag"
    git clone https://github.com/syndesisio/syndesis.git
    cd syndesis
    git checkout $syndesis_git_tag

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

    echo "==== Patch install script with correct Maven Repos"
    sed -e "s#\(02_redhat_ea_repository:\s*\).*#02_redhat: $maven_redhat_repository#" \
        -e "s#\(03_jboss_ea:\s*\).*#03_jboss: $maven_jboss_repository#" \
        -i "$topdir/resources/fuse-ignite-oso.yml" "$topdir/resources/fuse-ignite-ocp.yml"

    # SYNDESIS_VERSION is provided from template parameter, we should only patch repository coordinates
    echo "==== Patch install script with productized syndesis-upgrade images"
    sed -e "s#image:\s*syndesis/syndesis-upgrade.*#image: $docker_registry/$docker_image_repository/fuse-ignite-upgrade:\${SYNDESIS_VERSION}#" \
        -i "$topdir/resources/fuse-ignite-oso.yml" "$topdir/resources/fuse-ignite-ocp.yml"

    echo "==== Copy support SA"
    cp ../support/serviceaccount-as-oauthclient-restricted.yml \
       "$topdir/resources/serviceaccount-as-oauthclient-restricted.yml"

    echo "==== Patch install script with tag"
    sed -e "s/^TAG=.*\$/TAG=$fuse_ignite_tag/" -i $topdir/install_ocp.sh


    echo "==== Patch imagestream script with current versions"
    local brew_tag=$(readopt --version-brew)

    local fuse_ignite_server=$(read_image_version fuse-ignite-server $brew_tag)
    check_error $fuse_ignite_server
    local fuse_ignite_ui=$(read_image_version fuse-ignite-ui $brew_tag)
    check_error $fuse_ignite_ui
    local fuse_ignite_meta=$(read_image_version fuse-ignite-meta $brew_tag)
    check_error $fuse_ignite_meta
    local fuse_ignite_s2i=$(read_image_version fuse-ignite-s2i $brew_tag)
    check_error $fuse_ignite_s2i


    sed -e "s/{{[ ]*Tags.Ignite[ ]*}}/$is_tag/g" \
        -e "s/{{[ ]*Tags.Ignite.Server[ ]*}}/$fuse_ignite_server/g" \
        -e "s/{{[ ]*Tags.Ignite.Ui[ ]*}}/$fuse_ignite_ui/g" \
        -e "s/{{[ ]*Tags.Ignite.Meta[ ]*}}/$fuse_ignite_meta/g" \
        -e "s/{{[ ]*Tags.Ignite.S2I[ ]*}}/$fuse_ignite_s2i/g" \
        -e "s/{{[ ]*Docker.Registry[ ]*}}/$docker_registry/g" \
        -e "s/{{[ ]*Docker.Image.Repository[ ]*}}/$docker_image_repository/g" \
        $topdir/templates/fuse-ignite-image-streams.yml \
        > $topdir/resources/fuse-ignite-image-streams.yml

    popd
}

# Left over from 'syndesis release'
release() {
    local topdir=$1
    local syndesis_tag=$2
    local fuse_ignite_tag=$3

    create_templates $topdir $syndesis_tag $fuse_ignite_tag $docker_registry $docker_image_repository $maven_redhat_repository $maven_jboss_repository

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

docker_registry=$(readopt --docker-registry)
if [ -z "${docker_registry}" ]; then
    docker_registry="brew-pulp-docker01.web.prod.ext.phx2.redhat.com:8888"
fi

docker_image_repository=$(readopt --docker-image-repository)
if [ -z "${docker_image_repository}" ]; then
    docker_image_repository="jboss-fuse-7-tech-preview"
fi

maven_redhat_repository=$(readopt --maven-redhat-repository)
if [ -z "${maven_redhat_repository}" ]; then
    maven_redhat_repository="https://maven.repository.redhat.com/ga/"
fi

maven_jboss_repository=$(readopt --maven-jboss-repository)
if [ -z "${maven_jboss_repository}" ]; then
    maven_jboss_repository="https://repository.jboss.org/"
fi

release "$(basedir)" $syndesis_tag $fuse_ignite_tag $docker_registry $docker_image_repository $maven_redhat_repository $maven_jboss_repository
