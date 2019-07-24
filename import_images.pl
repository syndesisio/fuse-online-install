#!/usr/bin/perl

use Getopt::Long;
use Term::ANSIColor qw(:constants);
use FindBin;
use strict;

=head1 Transfering Docker images

This sript is from our pipeline/brew builds to our ignite cluster.
It will use the release information in fuse_ignite_config.sh for importing data to the respective imagestreams.

You have to be docker logged in into target repository. This can be easily done with

    docker login -u $(oc whoami) -p $(oc whoami -t) registry.online-stg.openshift.com

while being connected to the target OpenShift cluster. Adapt the registry name to your target registry.

By default the target registry is "registry.online-stg.openshift.com" and the target repo is "fuse-ignite".
You can change this with the options C<--registry> and C<--repository>, respectively.

=cut

# Target registry & repository can be overwritten
my $target_registry = "registry.online-stg.openshift.com";
my $target_repository = "fuse-ignite";
GetOptions("registry=s",\$target_registry,
           "repository=s",\$target_repository);

my $config = &parse_configuration();


my $RELEASE_MAP =
{
   "target" =>
    {
     "registry" => $target_registry,
     "repository" => $target_repository,
     "images" =>
       {
        "fuse-ignite-server" => "$config->{target_version}",
        "fuse-ignite-ui" => "$config->{target_version}",
        "fuse-ignite-meta" => "$config->{target_version}",
        "fuse-ignite-s2i" => "$config->{target_version}",
        "fuse-ignite-upgrade" => "$config->{target_version}",
        "fuse-online-operator" => "$config->{target_version}"
       }
    },
  "source" =>
    {
     "registry" => $config->{registry},
     "repository" => $config->{repository},
     "images" =>
       {
        "fuse-ignite-server" => $config->{tag_server},
        "fuse-ignite-ui" => $config->{tag_ui},
        "fuse-ignite-meta" => $config->{tag_meta},
        "fuse-ignite-s2i" => $config->{tag_s2i},
        "fuse-ignite-upgrade" => $config->{tag_upgrade},
        "fuse-online-operator" => $config->{tag_operator}
       }
    }
};

# Extra images to push
my $EXTRA_IMAGES =
  [
    {
      source => "registry.redhat.io/openshift4/ose-oauth-proxy:4.1",
      target =>  "oauth-proxy:v1.1.0"
    },
    {
      source => "registry.redhat.io/openshift3/prometheus:v3.9.25",
      target => "prometheus:v2.1.0"
    },
    {
      source => "$config->{registry}/fuse7-tech-preview/fuse-postgres-exporter:$config->{tag_postgres_exporter}",
      target => "postgres_exporter:v0.4.7"
    },
    {
      source => "$config->{registry}/fuse7-tech-preview/data-virtualization-server-rhel7:$config->{tag_komodo}",
      target => "fuse-komodo-server:latest"
    }
  ];

my $source = $RELEASE_MAP->{source};
my $target = $RELEASE_MAP->{target};

print RED,<<EOT,RESET;
==================================================================
Importing images from "$source->{registry}" to "$target->{registry}"
==================================================================
EOT

for my $image (sort keys %{$source->{images}}) {
    print YELLOW,"* ",GREEN,"Transfering ${image}:",$source->{images}->{$image},"\n",RESET;

    my $pulled_image = &docker_pull(&format_image($image,$source));
    my $tagged_image = &docker_tag($pulled_image, &format_image($image,$target));
    &docker_push($tagged_image);

    # Check for an additional patchlevel tag
    my $source_tag = $source->{images}->{$image};
    if ($source_tag =~ /^\d+\.\d+[.\-](\d+)$/) {
        my $patch_level = $1;
        my $tagged_image = &docker_tag($pulled_image, &format_image($image, $target), $patch_level);
        &docker_push($tagged_image);
    }
}


print RED,<<EOT,RESET;
=====================
Pushing extra images
=====================
EOT

for my $extra (@$EXTRA_IMAGES) {
    my $pulled_image = &docker_pull($extra->{source});
    my $tagged_image = &docker_tag($pulled_image, $target->{registry} . "/" . $target->{repository} . "/" . $extra->{target});
    &docker_push($tagged_image);
}

# ==============================================================================================
sub format_image {
    my $image = shift;
    my $map = shift;
    return sprintf("%s/%s/%s:%s",$map->{registry},$map->{repository},$image,$map->{images}->{$image});
}

sub docker_pull {
    my $src_image = shift;
    &exec_cmd("docker","pull",$src_image);
    return $src_image;
}

sub docker_tag {
    my $source_image = shift;
    my $target_image = shift;
    my $patch_level = shift;
    $target_image .= "." . $patch_level if defined($patch_level);
    &exec_cmd("docker","tag",$source_image,$target_image);
    return $target_image;
}

sub docker_push {
    my $target_image = shift;
    &exec_cmd("docker","push","$target_image");
}

sub exec_cmd {
    my @args = @_;
    print join " ",BLUE,@args[0..1],CYAN,"\n    ",@args[2],MAGENTA,"\n    ",@args[3..$#args],RESET,"\n";
    print BRIGHT_BLACK;
    system(@args) == 0 or die "command failed: $?";
    print RESET;
}

sub parse_configuration() {
  # Parse configuration
  my $config_file = $FindBin::Bin . "/fuse_online_config.sh";
  open(CONFIG,$config_file) || die "Cannot open $config_file: $!";
  my $config = {};
  while (my $line = <CONFIG>) {
    next if $line =~ /^\s*#/;
      if ($line =~ /^([^=]+?)\s*=\s*"?(.*?)"?\s*$/) {
          $config->{$1} = $2;
      }
  }
  close CONFIG;

  die "No registry given in $config_file" unless $config->{registry};
  die "No repository given in $config_file" unless $config->{repository};
  for my $img ("ui","server","meta","s2i", "upgrade") {
    die "No tag for $img provided in $config_file" unless $config->{"tag_" . $img}
  }
  die "No git_fuse_online_install given in $config_file" unless $config->{git_fuse_online_install};
  my $target_version = $1 if $config->{git_fuse_online_install} =~ /^(\d+\.\d+)(\.\d+)?$/;
  die "Could not extract target version (format: <major>.<minor>) from given git_fuse_online_install \"", $config->{git_fuse_online_install},"\" in $config_file" unless $target_version;
  $config->{target_version} = $target_version;
  return $config;
}

# Autoflush
BEGIN {
    $| = 1;
}
