# This template is used in Jenkins to enable property substitution at runtime

# Tag for release. Update this before running release.sh
git_fuse_online_install="version.fuse.online"

# Image Streams to be updated
imagestreams="server ui meta s2i postgres_exporter komodo"

# Tags used for the productised images
tag_server="version.tag.server"
tag_ui="version.tag.ui"
tag_meta="version.tag.meta"
tag_s2i="version.tag.s2i"
tag_postgres_exporter="version.tag.postgres"

tag_upgrade="version.tag.upgrade"
tag_operator="version.tag.operator"

tag_camel_k="version.tag.camel.k"
tag_java_base_image="version.tag.java.base.image"

tag_komodo="version.tag.komodo"


# Docker repository for productised images
repository="repo.name"

# Test:
registry="registry.name"
maven_repository="maven.repository.name"

# Official:
# registry="registry.access.redhat.com"
# maven_repository="https://maven.repository.redhat.com/ga@id=redhat.ga"
