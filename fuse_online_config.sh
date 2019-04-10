# This template is used in Jenkins to enable property substitution at runtime

# Tag for release. Update this before running release.sh
git_fuse_online_install="1.6.9"

# Tags used for the productised images
tag_server="1.3-9"
tag_ui="1.3-7"
tag_meta="1.3-9"
tag_s2i="1.3-9"

tag_upgrade="1.3-6"
tag_operator="1.3-6"
tag_postgres_exporter="1.3-2"


# Docker repository for productised images
repository="fuse7"

# Test:
registry="brew-pulp-docker01.web.prod.ext.phx2.redhat.com:8888"

# Official:
# registry="registry.access.redhat.com"
