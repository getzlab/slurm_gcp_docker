#!/bin/bash

. /sgcpd/slurm_gcp_docker/docker_init_credentials.sh

/sgcpd/slurm_gcp_docker/docker_copy_gcloud_credentials.sh

# Pull cluster config from GCS to node-local disk, if canine told us which
# bucket (via the cluster-config-bucket instance metadata attribute set by
# slurm_resume.py). Non-fatal by design: slurm_start.sh below falls back to the
# NFS copy, so a failure here degrades to today's behaviour rather than
# blocking boot. See NFS-FUSE-IMPLEMENTATION-PLAN.md phase 2.
/sgcpd/slurm_gcp_docker/fetch_cluster_config.sh || \
  echo "fetch_cluster_config failed; falling back to the NFS config copy" >&2

. /sgcpd/slurm_gcp_docker/slurm_start.sh
/sgcpd/slurm_gcp_docker/container_heartbeat.sh &
/bin/bash
