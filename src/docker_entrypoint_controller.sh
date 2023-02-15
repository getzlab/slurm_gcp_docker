#!/bin/bash

. /usr/local/share/slurm_gcp_docker/src/docker_init_credentials.sh

. /gcsdk/google-cloud-sdk/path.bash.inc

/usr/local/share/slurm_gcp_docker/src/docker_copy_gcloud_credentials.sh

mysqld --user root &
sudo -E -u $HOST_USER /usr/local/share/slurm_gcp_docker/src/provision_server.py
sudo -E -u $HOST_USER /bin/bash
