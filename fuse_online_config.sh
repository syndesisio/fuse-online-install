# Tag for release. Update this before running release.sh
git_fuse_online_install="master"

# Tags used for the productised images
imagestreams="server ui meta s2i postgres_exporter"
tag_server="1.2-12"
tag_ui="1.2-6"
tag_meta="1.2-12"
tag_s2i="1.2-9"
tag_upgrade="1.2-18"
tag_operator="1.2-13"
tag_postgres_exporter="1.3"
tag_camel_k="1.3"

# Docker repository for productised images
repository="fuse7"

# Test:
#registry="brew-pulp-docker01.web.prod.ext.phx2.redhat.com:8888"
#maven_repository="https://origin-repository.jboss.org/nexus/content/groups/ea@id=redhat.ea"

# Official:
registry="registry.redhat.io"
maven_repository="https://maven.repository.redhat.com/ga@id=redhat.ga"
