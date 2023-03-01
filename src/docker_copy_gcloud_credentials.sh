#!/bin/bash

# from read-only bind mount of controller gcloud, copy everything except logs folder (which can be large)
GCLOUD_PATHS=$(find /mnt/nfs/credentials/gcloud -mindepth 1 -maxdepth 1 ! -name "logs")

# add gcloud credentials to slurm's home directory
[ ! -d ~slurm/.config/gcloud ] && mkdir -p ~slurm/.config/gcloud
cp -r $GCLOUD_PATHS ~slurm/.config/gcloud && \
chown -R slurm:slurm ~slurm/.config/gcloud && \
ln -s ~slurm/.config/gcloud /global_gcloud_config

# add gcloud credentials to user's home directory
HOMEDIR=`eval echo ~$HOST_USER`
[ ! -d $HOMEDIR/.config/gcloud ] && mkdir -p $HOMEDIR/.config/gcloud
cp -r $GCLOUD_PATHS $HOMEDIR/.config/gcloud && chown -R $HOST_USER:$HOST_USER $HOMEDIR/.config/

# add Docker credentials to user's home directory
[ ! -d $HOMEDIR/.docker ] && mkdir -p $HOMEDIR/.docker
ln -s /usr/local/share/slurm_gcp_docker/conf/docker_config.json $HOMEDIR/.docker/config.json
