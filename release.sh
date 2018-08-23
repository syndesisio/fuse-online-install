#!/bin/bash

# Save global script args
ARGS=("$@")

# Exit if any error occurs
# Fail on a single failed command in a pipeline (if supported)
set -o pipefail

# Fail on error and undefined vars (please don't use global vars, but evaluation of functions for return values)
set -eu


display_usage() {
  cat <<EOT
Release tool for fuse-online templats

Usage: bash release.sh [options]

with options:

--help                       This help message
--create-templates           Only create templates but do not commit or push
--git-push                   Push to git directly
--verbose                    Verbose log output

Please check also "fuse_online_config.sh" for the configuration values.
EOT
}

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

create_resources() {
    local topdir=$1
    local fuse_online_tag=$2

    # Read in config variables
    source $topdir/fuse_online_config.sh

    local is_tag
    if [ "$fuse_online_tag" = "master" ]; then
        is_tag="latest"
    else
        is_tag=$(extract_minor_version $fuse_online_tag)
    fi

    echo "==== Patch install script with tag"
    sed -e "s/^TAG=.*\$/TAG=$fuse_online_tag/" -i.bak  $topdir/install_ocp.sh
    rm $topdir/install_ocp.sh.bak

    echo "==== Patch imagestream script with current versions"
    sed -e "s/{{[ ]*Tags.Online[ ]*}}/$is_tag/g" \
        -e "s/{{[ ]*Tags.Online.Operator[ ]*}}/$tag_operator/g" \
        -e "s/{{[ ]*Docker.Registry[ ]*}}/$registry/g" \
        -e "s/{{[ ]*Docker.Image.Repository[ ]*}}/$repository/g" \
        $topdir/templates/fuse-online-operator.yml \
        > $topdir/resources/fuse-online-operator.yml

    sed -e "s/{{[ ]*Tags.Online[ ]*}}/$is_tag/g" \
        -e "s/{{[ ]*Tags.Online.Server[ ]*}}/$tag_server/g" \
        -e "s/{{[ ]*Tags.Online.Ui[ ]*}}/$tag_ui/g" \
        -e "s/{{[ ]*Tags.Online.Meta[ ]*}}/$tag_meta/g" \
        -e "s/{{[ ]*Tags.Online.S2I[ ]*}}/$tag_s2i/g" \
        -e "s/{{[ ]*Docker.Registry[ ]*}}/$registry/g" \
        -e "s/{{[ ]*Docker.Image.Repository[ ]*}}/$repository/g" \
        $topdir/templates/fuse-online-image-streams.yml \
        > $topdir/resources/fuse-online-image-streams.yml

    sed -e "s/{{[ ]*Tags.Online.Upgrade[ ]*}}/$tag_upgrade/g" \
        -e "s/{{[ ]*Docker.Registry[ ]*}}/$registry/g" \
        -e "s/{{[ ]*Docker.Image.Repository[ ]*}}/$repository/g" \
        $topdir/templates/fuse-online-upgrade.yml \
        > $topdir/resources/fuse-online-upgrade.yml

    echo "==== Extract Template from Operator image"
    docker run -v $(pwd)/resources:/resources \
               --entrypoint bash \
               $registry/$repository/fuse-online-operator:$tag_operator \
               -c "cp /conf/syndesis-template.yml /resources/fuse-online-template.yml"
}

release() {
    local topdir=$1

    source $topdir/fuse_online_config.sh

    if [ -z "$git_fuse_online_install" ]; then
        echo "ERROR: No config property git_fuse_online_install configured in 'fuse_online_config.sh'"
        exit 1
    fi

    create_resources $topdir $git_fuse_online_install

    if [ $(hasflag --template-only) ]; then
        return
    fi

    echo "==== Committing"
    cd $topdir
    git_commit "resources/" "Update Operator resources" "$git_fuse_online_install"
    git_commit "fuse_online_config.sh" "Update release config for $git_fuse_online_install" "$git_fuse_online_install"
    git_commit "install_ocp.sh" "Update release config for $git_fuse_online_install" "$git_fuse_online_install"

    # No tagging when just running on master
    if [ $git_fuse_online_install = "master" ]; then
        return
    fi

    echo "=== Tagging $git_fuse_online_install"
    git tag -f "${git_fuse_online_install}"

    local moving_tag=$(extract_minor_version $git_fuse_online_install)
    check_error $moving_tag

    echo "=== Moving tag $moving_tag"
    git tag -f "${moving_tag}"

    # Push release tag only
    git_push "$topdir" "$git_fuse_online_install" "$moving_tag"
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
