#!/bin/bash

. /sgcpd/src/docker_init_credentials.sh

/sgcpd/src/docker_copy_gcloud_credentials.sh

. /sgcpd/src/slurm_start.sh
/sgcpd/src/container_heartbeat.sh &
/bin/bash
