#!/bin/bash

# add gcloud credentials to slurm's home directory
[ ! -d ~slurm/.config ] && mkdir -p ~slurm/.config
cp -r /mnt/nfs/clust_conf/gcloud ~slurm/.config/gcloud && \
chown -R slurm:slurm ~slurm/.config/gcloud

# add gcloud credentials to user's home directory
HOMEDIR=`eval echo ~$HOST_USER`
[ ! -d $HOMEDIR/.config ] && mkdir -p $HOMEDIR/.config
cp -r /mnt/nfs/clust_conf/gcloud $HOMEDIR/.config/gcloud && chown -R $HOST_USER:$HOST_USER $HOMEDIR/.config/

# add Docker credentials to user's home directory
[ ! -d $HOMEDIR/.docker ] && mkdir -p $HOMEDIR/.docker
ln -s /usr/local/share/slurm_gcp_docker/conf/docker_config.json $HOMEDIR/.docker/config.json
