#!/bin/bash

# install NFS, Docker, associated files, gcloud
cat <<EOF
# NFS
sudo apt-get update && sudo apt-get -y install git nfs-kernel-server nfs-common portmap ssed iptables && \
# DOCKER
sudo groupadd -g 1338 docker && \
sudo apt-get install -y docker.io && \
sudo chmod 666 /var/run/docker.sock
# ENABLE CGROUPS
sudo ssed -R -i '/GRUB_CMDLINE_LINUX=/s/(.*)"(.*)"(.*)/\1"\2 cgroup_enable=memory swapaccount=1 systemd.unified_cgroup_hierarchy=0"\3/' /etc/default/grub && \
sudo update-grub && \
# INSTALL GCLOUD
[ ! -d ~$USER/.config/gcloud ] && sudo -u $USER mkdir -p ~$USER/.config/gcloud
sudo mkdir /gcsdk && \
sudo wget -O gcs.tgz https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-318.0.0-linux-x86_64.tar.gz && \
sudo tar xzf gcs.tgz -C /gcsdk && \
sudo /gcsdk/google-cloud-sdk/install.sh --usage-reporting false --path-update true --quiet && \
sudo ln -s /gcsdk/google-cloud-sdk/bin/* /usr/bin
EOF

cat <<'EOF'
#NVIDIA DRIVER
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nvidia-driver-450
export distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
      && curl -s -L https://nvidia.github.io/libnvidia-container/experimental/$distribution/libnvidia-container.list | \
         sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
         sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update
sudo apt-get install -y nvidia-docker2
sudo systemctl restart docker
EOF

# make sure shutdown script that tells Slurm controller node is going offline
# runs before the Docker daemon shuts down
echo "[ ! -d /etc/systemd/system/google-shutdown-scripts.service.d ] && \
sudo mkdir -p /etc/systemd/system/google-shutdown-scripts.service.d; \
sudo tee /etc/systemd/system/google-shutdown-scripts.service.d/override.conf > /dev/null <<EOF
[Unit]
After=docker.service
After=docker.socket
EOF"

# Wait for transferring the docker base image (generate_container_host_image.py)
echo "touch /started"

# Load docker base image
echo "while ! [ -f /data_transferred ]; do sleep 1; done"
echo "sudo docker load -i /tmp/tmp_docker_file"

# build current user into container
VERSION=$(cat VERSION)
docker_base_image=$(cat DOCKER_SRC)
echo "sudo docker build -t broadinstitute/slurm_gcp_docker:$VERSION \
  -t broadinstitute/slurm_gcp_docker:latest \
  --build-arg HOST_USER=$USER --build-arg UID=$UID --build-arg GID=$(id -g) \
  --build-arg DOCKER_BASE_IMAGE=$docker_base_image:$VERSION \
  /usr/local/share/slurm_gcp_docker/src"

echo "touch /completed"
