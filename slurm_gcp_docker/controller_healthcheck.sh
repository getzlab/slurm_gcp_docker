#!/bin/bash

ZONE=$(basename $(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone 2> /dev/null))

while true; do 
	# kill all running hosts that slurm thinks are "down"
	# sinfo --format %N -t down -Nh -p all | grep -Fx -f - <(gcloud compute instances list --format="csv(name)") | xargs gcloud compute instances delete

	#
	# resume all down hosts
	scontrol update nodename=$(sinfo -h --format %N -t down -p all) state=resume

	# release stuck jobs
	squeue -t PD -o '%i'$'\t''%R' | awk -F'\t' '$2 == "(launch failed requeued held)" { print $1 }' | xargs scontrol release

	# check for resource contraints; pause jobs
	# TODO

	sleep 600
done
