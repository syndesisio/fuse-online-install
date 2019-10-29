

NOTE: The templates are deprecated and should not be used. We keep them to support legacy systems.

# Setup preparations

The following steps mimic the fuse online provisioning app that's used with the eval cluster.

## Namespace Setup

```
oc new-project fuse-ignite
oc new-project syndesis
```

## Install the template into a separate namespace

```
oc project fuse-ignite
oc create -f fuse-online-template.yml
```

## Setup OAuth Service Account

```
oc project syndesis
oc create -f templates/serviceaccount-as-oauthclient-restricted.yml
```

# Install Fuse Online

```
oc new-app --template=fuse-ignite/fuse-ignite-1.8 -p OPENSHIFT_OAUTH_CLIENT_SECRET=$(oc sa get-token syndesis-oauth-client -n syndesis) -p IMAGE_STREAM_NAMESPACE-fuse-ignite -p OPENSHIFT_PROJECT=syndesis -p SAR_PROJECT=syndesis -p ROUTE_HOSTNAME=$(minishift ip) -n syndesis
```
