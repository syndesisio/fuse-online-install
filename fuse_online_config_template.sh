# This template is used in Jenkins to enable property substitution at runtime

# Tag for release. Update this before running release.sh
git_fuse_online_install="version.fuse.online"

# Tags used for the productised images
tag_server="version.tag.server"
tag_ui="version.tag.ui"
tag_meta="version.tag.meta"
tag_s2i="version.tag.s2i"

tag_upgrade="version.tag.upgrade"
tag_operator="version.tag.operator"


# Docker repository for productised images
repository="repo.name"

# Test:
registry="registry.name"

# Official:
# registry="registry.access.redhat.com"
