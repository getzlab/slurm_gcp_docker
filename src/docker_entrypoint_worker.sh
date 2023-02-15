#!/bin/bash

. /usr/local/share/slurm_gcp_docker/src/docker_init_credentials.sh

sudo -E /usr/local/share/slurm_gcp_docker/src/docker_copy_gcloud_credentials.sh

. /usr/local/share/slurm_gcp_docker/src/slurm_start.sh
/usr/local/share/slurm_gcp_docker/src/container_heartbeat.sh &
/bin/bash
