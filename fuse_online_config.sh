# Tag for release. Update this before running release.sh
git_fuse_online_install="1.7.24"

# Image Streams to be updated
imagestreams="server ui meta s2i"

# Tags used for the productised images
tag_server="1.4-14"
tag_ui="1.4-6"
tag_meta="1.4-13"
tag_s2i="1.4-13"

tag_upgrade="1.4-8"
tag_operator="1.4-11"
tag_postgres_exporter="1.4-4"

tag_camel_k="1.4-13"
tag_java_base_image="1.4-14"

tag_komodo="1.4-15"

# Docker repository for productised images
repository="fuse7"
repository_tech_preview="fuse7-tech-preview"

# Test:
registry="brew-pulp-docker01.web.prod.ext.phx2.redhat.com:8888"
maven_repository="https://origin-repository.jboss.org/nexus/content/groups/ea@id=redhat.ea"

# Official:
#registry="registry.redhat.io"
#maven_repository="https://maven.repository.redhat.com/ga@id=redhat.ga"
