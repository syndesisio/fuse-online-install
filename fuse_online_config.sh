# Tag for release. Update this before running release.sh
git_fuse_online_install="1.7.4"

# Image Streams to be updated
imagestreams="server ui meta s2i postgres_exporter komodo"

# Tags used for the productised images
tag_server="1.4-5"
tag_ui="1.4-2"
tag_meta="1.4-4"
tag_s2i="1.4-4"

tag_upgrade="1.4-2"
tag_operator="1.4-4"
tag_postgres_exporter="1.4-1"

tag_camel_k="1.4-1"
tag_java_base_image="1.4-7"

tag_komodo="1.4-3"

# Docker repository for productised images
repository="fuse7"

# Test:
registry="brew-pulp-docker01.web.prod.ext.phx2.redhat.com:8888"
maven_repository="https://origin-repository.jboss.org/nexus/content/groups/ea@id=redhat.ea"

# Official:
#registry="registry.redhat.io"
#maven_repository="https://maven.repository.redhat.com/ga@id=redhat.ga"
