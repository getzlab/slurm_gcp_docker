#!/bin/bash

ZONE=$(basename $(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone 2> /dev/null))

while true; do 
	# kill all running hosts that slurm thinks are "down"
	# sinfo --format %N -t down -Nh -p all | grep -Fx -f - <(gcloud compute instances list --format="csv(name)") | xargs gcloud compute instances delete

	#
	# resume all down hosts
	scontrol update nodename=$(sinfo -h --format %N -t down -p all) state=resume

	#
	# increase disks' sizes
	# for each persistent disk attached to instance,
	for DISK_DEV in $(find /dev/disk/by-id -name "google*"); do
		GOOGLE_DISK_NAME=$(sed 's|/dev/disk/by-id/google-||' <<< "$DISK_DEV")
		# if this persistent disk is mounted to wolF NFS, check if it's low on space
		if df $DISK_DEV | grep -q /mnt/nfs; then
			DISK_SIZE_GB=$(df -B1G $DISK_DEV | awk 'NR == 2 { print int($3 + $4) }')
			FREE_SPACE_GB=$(df -B1G $DISK_DEV | awk 'NR == 2 { print int($4) }')
			if [[ $((100*FREE_SPACE_GB/DISK_SIZE_GB)) -lt 10 ]]; then
				gcloud_exp_backoff compute disks resize $GOOGLE_DISK_NAME --quiet --zone $ZONE --size $((DISK_SIZE_GB+50))
				sudo resize2fs $DISK_DEV
			fi
		fi
	done

	# release stuck jobs
	squeue -t PD -o '%i'$'\t''%R' | awk -F'\t' '$2 == "(launch failed requeued held)" { print $1 }' | xargs scontrol release

	# check for resource contraints; pause jobs
	# TODO

	sleep 600
done
