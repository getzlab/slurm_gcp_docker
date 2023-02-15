#!/bin/bash

. /usr/local/share/slurm_gcp_docker/src/docker_init_credentials.sh

. /gcsdk/google-cloud-sdk/path.bash.inc

sudo -E /usr/local/share/slurm_gcp_docker/src/docker_copy_gcloud_credentials.sh

sudo mysqld --user root &
/usr/local/share/slurm_gcp_docker/src/provision_server.py
export SLURM_CONF=/mnt/nfs/clust_conf/slurm/slurm.conf
/bin/bash
