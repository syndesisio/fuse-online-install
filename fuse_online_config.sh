# This template is used in Jenkins to enable property substitution at runtime

# Tag for release. Update this before running release.sh
git_fuse_online_install="1.6.20"

# Tags used for the productised images
tag_server="1.3-16"
tag_ui="1.3-10"
tag_meta="1.3-16"
tag_s2i="1.3-16"

tag_upgrade="1.3-9"
tag_operator="1.3-9"
tag_postgres_exporter="1.3-4"

tag_camel_k="1.3-4"
tag_java_base_image="1.3-10"

# Docker repository for productised images
repository="fuse7"

registry="registry.redhat.io"
maven_repository="https://maven.repository.redhat.com/ga@id=redhat.ga"
