#!/bin/bash
#
# Functions related to downloading CLI artifacts

source "$BASEDIR/common_config.sh"

get_syndesis_bin() {
  get_cli_bin $SYNDESIS_DOWNLOAD_URL $SYNDESIS_BINARY $SYNDESIS_VERSION
}

# Download CLI
get_cli_bin() {
  local url=${1}
  local name=${2}
  local version=${3}
  local bin_dir=${4:-/tmp}

  local cli_command="$bin_dir/${name}-${version}${BINARY_FILE_EXTENSION}"
  if [ -e $cli_command ]; then
    echo $cli_command
    return
  fi

  local archive=$(mktemp $bin_dir/${name}-${version}.tar-XXXX)

  # Download from remote site
  set +e
  curl --fail -sL -o $archive $url >$ERROR_FILE 2>&1
  if [ $? -ne 0 ]; then
      echo "ERROR: Cannot download file from $url"
      set -e
      return
  fi
  set -e

  local tmp_dir=$(mktemp -d $bin_dir/${name}-${version}-XXXX)
  pushd $tmp_dir >/dev/null

  set +e
  tar xf $archive >$ERROR_FILE 2>&1
  if [ $? -ne 0 ]; then
      echo "ERROR: Cannot extract downloaded file"
      set -e
      return
  fi
  set -e

  set +e
  local binary_file=./${name}${BINARY_FILE_EXTENSION}
  mv $binary_file $cli_command >$ERROR_FILE 2>&1
  if [ $? -ne 0 ]; then
      echo "ERROR: Cannot move binary file $binary_file to $cli_command"
      set -e
      return
  fi
  set -e

  popd >/dev/null
  [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ] && rm -rf $tmp_dir
  echo $cli_command
}
