#!/bin/bash

#
# run on the worker node as the node shutdown script (as provisioned in slurm_resume.py,
# with script path sourced from pickled config file saved from backend)

# check if node is actually being preempted
# shutdown script will run if systemd restarts; we don't want this to cause the node to powerdown
if [ $(curl "http://metadata.google.internal/computeMetadata/v1/instance/preempted" -H "Metadata-Flavor: Google" 2> /dev/null) == "FALSE" ]; then
  exit 0
fi

# alert controller that this host is being preempted; set status to fail
docker exec slurm scontrol update nodename=$HOSTNAME state=FAIL reason="shutdown triggered" && \
docker exec slurm scontrol update nodename=$HOSTNAME state=DOWN reason="shutdown triggered" && \
docker exec slurm scontrol update nodename=$HOSTNAME state=POWER_DOWN reason="powerdown"

#
# detach any RO disks

# get zone of instance
ZONE=$(basename $(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone 2> /dev/null))

find /dev/disk/by-id -name "google-canine*" | grep -o 'canine-.*$' | \
  xargs -I {} -n 1 -P 0 docker exec slurm gcloud compute instances detach-disk $HOSTNAME --device-name {} --zone $ZONE
