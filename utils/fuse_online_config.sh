
base_image_version=1.5

# Image Streams to be updated
imagestreams="server ui meta s2i postgres_exporter komodo"

# Tags used for the productised images
tag_server="1.5"
tag_ui="1.5"
tag_meta="1.5"
tag_s2i="1.5"

tag_upgrade="1.5"
tag_operator="1.5"
tag_postgres_exporter="1.5"

tag_camel_k="1.5"
tag_java_base_image="1.5"

tag_komodo="1.5"

# Docker repository for productised images
repository="fuse7"

# Test:
#registry="registry-proxy.engineering.redhat.com/rh-osbs"
#maven_repository="https://origin-repository.jboss.org/nexus/content/groups/ea@id=redhat.ea"

# Official:
registry="registry.redhat.io"
maven_repository="https://maven.repository.redhat.com/ga@id=redhat.ga"
