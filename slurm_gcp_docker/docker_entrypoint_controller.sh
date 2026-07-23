#!/bin/bash

. /sgcpd/slurm_gcp_docker/docker_init_credentials.sh

. /gcsdk/google-cloud-sdk/path.bash.inc

/sgcpd/slurm_gcp_docker/docker_copy_gcloud_credentials.sh

mysqld --user root &
sudo -E -u $HOST_USER /sgcpd/slurm_gcp_docker/provision_server.py
/sgcpd/slurm_gcp_docker/controller_healthcheck.sh &
/sgcpd/slurm_gcp_docker/controller_disk_resize.sh &
sudo -E -u $HOST_USER /bin/bash
