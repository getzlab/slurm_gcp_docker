#!/bin/bash

# Prefer node-local config, fall back to the NFS mount (cluster_conf_paths.sh).
# Unlike slurm_start.sh this must not block -- Slurm invokes it as
# SuspendProgram and a hang here would stall node teardown -- so resolve
# directly and accept the NFS path if local config is absent.
. /sgcpd/slurm_gcp_docker/cluster_conf_paths.sh
export SLURM_CONF="$(resolve_cluster_conf_dir)/slurm/slurm.conf"
export CLOUDSDK_CONFIG=/slurm_gcloud_config

# assume zone of instance is the same as the zone of the controller
# because gcloud list API requests are highly throttled, this approach is much
# cheaper -- we don't expect to be running multi-zone clusters due to their
# poor performance
ZONE=$(basename $(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone 2> /dev/null))

INST_LIST=$(scontrol show hostnames $@)

# XXX: gcloud assumes that sys.stdin will always be not None, so we need to pass
#      dummy stdin (/dev/null)
/sgcpd/slurm_gcp_docker/docker_bin/gcloud_exp_backoff 320 compute instances delete $INST_LIST --zone $ZONE --quiet < /dev/null
