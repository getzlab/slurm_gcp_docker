#!/bin/bash

# install NFS, Docker, cgroups
cat <<'EOF'
# NFS
sudo apt-get update && sudo apt-get -y install git nfs-kernel-server nfs-common portmap ssed iptables && \
# DOCKER
sudo apt-get install -y docker.io && \
# ENABLE CGROUPS
sudo ssed -R -i '/GRUB_CMDLINE_LINUX=/s/(.*)"(.*)"(.*)/\1"\2 cgroup_enable=memory swapaccount=1 systemd.unified_cgroup_hierarchy=0"\3/' /etc/default/grub && \
sudo update-grub
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

# Wait for transferring the Slurm Docker
echo "touch /started"
echo "while ! [ -f /data_transferred ]; do sleep 1; done"
echo "sudo docker load -i /tmp/tmp_docker_file"
echo "touch /completed"
