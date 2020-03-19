
base_image_version=1.6

# Image Streams to be updated
imagestreams="server ui meta s2i postgres_exporter komodo"

# Tags used for the productised images
tag_server="1.6"
tag_ui="1.6"
tag_meta="1.6"
tag_s2i="1.6"

tag_upgrade="1.6"
tag_operator="1.6"
tag_postgres_exporter="1.6"

tag_camel_k="1.6"
tag_java_base_image="1.6"

tag_komodo="1.6"

# Docker repository for productised images
repository="fuse7"

# Test:
registry="registry-proxy.engineering.redhat.com/rh-osbs"
maven_repository="https://origin-repository.jboss.org/nexus/content/groups/ea@id=redhat.ea"

# Official:
#registry="registry.redhat.io"
#maven_repository="https://maven.repository.redhat.com/ga@id=redhat.ga"
