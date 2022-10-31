#!/bin/bash

# runs inside each worker container, checks every 5 minutes if the container is
# healthy. if not, blacklist this node.

export CLOUDSDK_CONFIG=/etc/gcloud

# get zone of instance
ZONE=$(basename $(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone 2> /dev/null))

# create instance logfile
export LOGFILE=/mnt/nfs/clust_logs/${HOSTNAME}.heartbeat.log
[ -f $LOGFILE ] && rm -f $LOGFILE

# run separate daemon to detect hung disks
/usr/local/share/slurm_gcp_docker/src/hung_disk_daemon.py & 2>&1 >> $LOGFILE

while true; do
	# check if Podman is responsive
	if ! timeout 30 podman info; then
		echo "`date` podman flatlined" >> $LOGFILE
		scontrol update nodename=$HOSTNAME state=FAIL reason="podman flatlined" && \
		gcloud compute instances delete $HOSTNAME --zone $ZONE --quiet
	fi

	# check if disk is full (<5% space remaining on root partition)
	if ! df / | awk 'NR == 2 { if($4/($4 + $3) < 0.05) { exit 1 } }'; then
		echo "`date` local disk full" >> $LOGFILE
		scontrol update nodename=$HOSTNAME state=FAIL reason="local disk full" && \
		gcloud compute instances delete $HOSTNAME --zone $ZONE --quiet
	fi

	# check if this node had problems attaching a disk (as reported by a task's
	# localization script)
	if [ -f /.fatal_disk_issue_sentinel ]; then
		echo "`date` fatal disk issue" >> $LOGFILE
		scontrol update nodename=$HOSTNAME state=FAIL reason="disk attach problems" && \
		gcloud compute instances delete $HOSTNAME --zone $ZONE --quiet
	fi

	# check if controller is responding; self-destruct if not
	timeout 30 bash -c 'scontrol ping | grep -q "is DOWN"'
	RC=$?
	if [[ $RC == 124 || $RC == 0 ]]; then # 124 -> timeout; 0 -> grep succeeded
		timeout 1 bash -c "echo \"`date` self-destructing due to nonresponsive controller!\" >> $LOGFILE"
		gcloud compute instances delete $HOSTNAME --zone $ZONE --quiet
	fi

	sleep 300
done
