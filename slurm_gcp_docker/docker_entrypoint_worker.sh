#!/bin/bash

. /sgcpd/slurm_gcp_docker/docker_init_credentials.sh

/sgcpd/slurm_gcp_docker/docker_copy_gcloud_credentials.sh

. /sgcpd/slurm_gcp_docker/slurm_start.sh
/sgcpd/slurm_gcp_docker/container_heartbeat.sh &
/bin/bash
