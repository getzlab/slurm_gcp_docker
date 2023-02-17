#!/bin/bash

set -e

# mount NFS
CONTROLLER_NAME=$(curl "http://metadata.google.internal/computeMetadata/v1/instance/attributes/slurm-controller-hostname" -H "Metadata-Flavor: Google")

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

# start Slurm docker
. /mnt/nfs/clust_scripts/docker_run.sh
