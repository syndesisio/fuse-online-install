#!/bin/bash
#
# Functions related to extracting artifacts from docker images

source "$BASEDIR/common_config.sh"

# Download CLI
extract_from_docker() {
  local image=${1}

  # If list contains more than 1 then each
  # separated by a semi-colon
  local filelist=${2}
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

  local IFS=';'
  for dfile in $filelist
  do
    docker run -u root -v $destination/:/client:z \
               --entrypoint bash \
               $image\
               -c "cp --dereference -r $dfile /client/; chmod -R a+rw /client/" >$ERROR_FILE 2>&1
    local err=$?
    set -e
    if [ $err -ne 0 ]; then
      echo "ERROR: Cannot extract requested artifacts from image $image."
      return
    fi
  done
}
