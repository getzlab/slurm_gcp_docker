#!/bin/bash

#
# run on the worker node as the node shutdown script (as provisioned in slurm_resume.py,
# with script path sourced from pickled config file saved from backend)

# alert controller that this host is being preempted; set status to fail
docker exec slurm scontrol update nodename=$HOSTNAME state=FAIL reason="shutdown triggered" && \
docker exec slurm scontrol update nodename=$HOSTNAME state=DOWN reason="shutdown triggered" && \
docker exec slurm scontrol update nodename=$HOSTNAME state=POWER_DOWN reason="powerdown"

#
# detach any RO disks

# get zone of instance
ZONE=$(basename $(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone 2> /dev/null))

# detach all RO disks
export CLOUDSDK_CONFIG=/etc/gcloud
ls -1 /dev/disk/by-id/google-gsdisk* | grep -o 'gsdisk-.*$' | \
  xargs -I {} -n 1 -P 0 gcloud compute instances detach-disk $HOSTNAME --device-name {} --zone $ZONE
