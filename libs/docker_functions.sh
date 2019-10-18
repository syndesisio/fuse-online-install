#!/bin/bash
#
# Functions related to extracting artifacts from docker images

source $BASEDIR/common_config.sh

# Download CLI
extract_from_docker() {
  local image=${1}
  local files=${2}
  local destination=${3}

  set +e
  docker pull $image >$ERROR_FILE 2>&1
  local err=$?
  set -e
  if [ $err -ne 0 ]; then
    echo "ERROR: Cannot pull image $image."
    return
  fi

  set +e
  docker run -u root -v $destination/:/client:z \
               --entrypoint bash \
               $image\
               -c "cp --dereference -r $files /client/; chmod -R a+rw /client/" >$ERROR_FILE 2>&1
  local err=$?
  set -e
  if [ $err -ne 0 ]; then
    echo "ERROR: Cannot copy client binaries from image $image."
    return
  fi
}
