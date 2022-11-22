#!/bin/bash

# install NFS - Docker - associated files - gcloud

# ENABLE OS-LOGIN FOR ALT SHELLS
apt update
apt -y install tcsh zsh

# NFS
apt -y install git nfs-kernel-server nfs-common portmap ssed iptables

# DOCKER
groupadd -g 1338 docker
apt -y install docker.io
chmod 666 /var/run/docker.sock

# ENABLE CGROUPS
ssed -R -i '/GRUB_CMDLINE_LINUX=/s/(.*)"(.*)"(.*)/\1"\2 cgroup_enable=memory swapaccount=1 systemd.unified_cgroup_hierarchy=0"\3/' /etc/default/grub
update-grub

# INSTALL GCLOUD
[ ! -d ~$USER/.config/gcloud ] && sudo -u $USER mkdir -p ~$USER/.config/gcloud
mkdir /gcsdk
wget -O gcs.tgz https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-318.0.0-linux-x86_64.tar.gz
tar xzf gcs.tgz -C /gcsdk
/gcsdk/google-cloud-sdk/install.sh --usage-reporting false --path-update true --quiet
ln -s /gcsdk/google-cloud-sdk/bin/* /usr/bin

# make sure shutdown script that tells Slurm controller node is going offline
# runs before the Docker daemon shuts down
[ ! -d /etc/systemd/system/google-shutdown-scripts.service.d ] && \
mkdir -p /etc/systemd/system/google-shutdown-scripts.service.d; \
tee /etc/systemd/system/google-shutdown-scripts.service.d/override.conf > /dev/null <<EOF
[Unit]
After=docker.service
After=docker.socket
EOF

# Wait for transferring the docker base image (generate_container_host_image.py)
touch /started

# Load docker base image
while ! [ -f /data_transferred ]; do sleep 1; done
docker load -i /tmp/tmp_docker_file

# build current user into container
docker build -t broadinstitute/slurm_gcp_docker:$VERSION \
  -t broadinstitute/slurm_gcp_docker:latest \
  --build-arg HOST_USER=$USER --build-arg UID=$UID --build-arg GID=$EGID \
  --build-arg DOCKER_BASE_IMAGE=$docker_base_image:$VERSION \
  /usr/local/share/slurm_gcp_docker/src

touch /completed
