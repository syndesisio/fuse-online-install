# This template is used in Jenkins to enable property substitution at runtime

# Tag for release. Update this before running release.sh
git_fuse_online_install="1.6.21"

# Tags used for the productised images
tag_server="1.3-19"
tag_ui="1.3-12"
tag_meta="1.3-19"
tag_s2i="1.3-19"

tag_upgrade="1.3-12"
tag_operator="1.3-13"
tag_postgres_exporter="1.3-5"

tag_camel_k="1.3-7"
tag_java_base_image="1.3-12"

# Docker repository for productised images
repository="fuse7"

registry="brew-pulp-docker01.web.prod.ext.phx2.redhat.com:8888"
maven_repository="https://origin-repository.jboss.org/nexus/content/groups/ea@id=redhat.ea"
