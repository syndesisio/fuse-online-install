#!/bin/bash
#
# Base functions for install scripts

check_error() {
    local msg="$*"
    local umsg==${msg^^} # Upper-case everything to ensure 'error' is detected as well as 'ERROR'
    if [ "${umsg//ERROR/}" != "${umsg}" ]; then
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
        # The word 'error' can be upper or lower case
        if grep -q "ERROR\|error" $error_file; then
            cat $error_file
        fi
        rm $error_file
    fi
}

#
# Only initialize ERROR_FILE once regardless of how many times
# this file is sourced, ie. its sourced by other scripts directly
# or indirectly when sourced by common_config.sh
#
if [ -z ${ERROR_FILE+x} ]; then
    ERROR_FILE="$(mktemp /tmp/syndesis-output-XXXXX)"
    trap "print_error $ERROR_FILE" EXIT
fi

get_executable_file_extension() {
    local os=$(get_current_os)
    if $(is_windows); then
        echo ".exe"
    fi
}

get_current_os() {
    # Check for proper operating system
    local os="linux"
    if $(is_mac_os); then
      os="mac"
    elif $(is_windows); then
      os="windows"
    fi
    echo $os
}

is_mac_os() {
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

is_windows() {
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
