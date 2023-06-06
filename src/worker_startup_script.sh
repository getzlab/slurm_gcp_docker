#!/bin/bash

set -e

## placeholders for environment variables that will be subsequently be burned
 # into this script by provision_server.py
export CONTROLLER_NAME=
export HOST_USER=
export HOST_UID=
export HOST_GID=

## mount NFS
echo "Starting NFS ..."

[ ! -d /mnt/nfs ] && sudo mkdir -p /mnt/nfs

# check if mount is stale
timeout 30 stat -t /mnt/nfs &> /dev/null
EC=$?
if [[ $EC == 124 ]]; then
	# attempt to unmount
	echo -n "NFS mount is stale; attempting unmount ..." > /dev/stderr
	if ! sudo timeout 2 umount -f /mnt/nfs; then
		echo -e "\nUnmount failed. Please close any open files (check with \`lsof -b | grep /mnt/nfs\`) and then \`sudo umount -f /mnt/nfs\`." > /dev/stderr
		exit 1
	fi
	echo " success!"
fi

# otherwise, wait for mount to be ready (NFS server is starting up)
echo -n "Waiting for NFS server to be ready ..."
while ! mountpoint -q /mnt/nfs; do
	sudo mount -o defaults,hard,intr ${CONTROLLER_NAME}:/mnt/nfs /mnt/nfs &> /dev/null
	echo -n "."
	sleep 1
done
echo

# mount rclone drives if they exist
for mount_script in $(find /mnt/nfs/ -maxdepth 1 -name ".rclone*.sh"); do
	source $mount_script
done

## start Slurm docker

# resolves occasional quota exceeded error, per https://stackoverflow.com/questions/54405454/error-response-from-daemon-join-session-keyring-create-session-key-disk-quota
# these values come from root_max{keys,bytes}
echo 1000000 > /proc/sys/kernel/keys/maxkeys
echo 25000000 > /proc/sys/kernel/keys/maxbytes

# only set gpu flags if gpu is attached
nvidia-smi && GPU_FLAGS="--gpus all"
# allow docker to use full extent of shared memory
SHM_SIZE=$(df -h -BM --output=size /dev/shm | sed 1d | awk '{print tolower($0)}')

# start the container

docker run -dti --rm --pid host --network host --privileged \
  -v /mnt/nfs:/mnt/nfs -v /sys/fs/cgroup:/sys/fs/cgroup \
  -v /var/run/docker.sock:/var/run/docker.sock -v /usr/bin/docker:/usr/bin/docker \
  -v /dev:/dev ${GPU_FLAGS} --shm-size ${SHM_SIZE} \
  --entrypoint /sgcpd/src/docker_entrypoint_worker.sh --name slurm \
  -e HOST_USER -e HOST_UID -e HOST_GID \
  broadinstitute/slurm_gcp_docker
