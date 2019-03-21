# ============================================================
# Helper functions common for install_ocp.sh and update_ocp.sh
# ============================================================

# Check whether syndesis-pull-secret secret is present and create
# it otherwise
#
create_secret_if_not_present() {
  if oc get secret syndesis-pull-secret >/dev/null 2>&1 ; then
    echo "pull secret 'syndesis-pull-secret' present, skipping creation ..."
  else
    echo "pull secret 'syndesis-pull-secret' is missing, creating ..."
    echo "enter username for registry.redhat.io and press [ENTER]: "
    read username
    echo "enter password for registry.redhat.io and press [ENTER]: "
    read -s password
    local result=$(oc create secret docker-registry syndesis-pull-secret --docker-server=registry.redhat.io --docker-username=$username --docker-password=$password)
    check_error $result
  fi
}
