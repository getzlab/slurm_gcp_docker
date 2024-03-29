#!/bin/bash

# runs inside each worker container, checks every 5 minutes if the container is
# healthy. if not, blacklist this node.

export CLOUDSDK_CONFIG=/slurm_gcloud_config

# add exponential backoff to all gcloud commands
shopt -s expand_aliases
alias gcloud=gcloud_exp_backoff

# create instance logfile
export LOGFILE=/mnt/nfs/clust_logs/${HOSTNAME}.heartbeat.log
[ -f $LOGFILE ] && rm -f $LOGFILE
exec > $LOGFILE 2>&1

# get zone of instance
ZONE=$(basename $(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone 2> /dev/null))

# run separate daemon to detect hung disks
/sgcpd/src/hung_disk_daemon.py &

# run separate daemon to automatically resize boot disk
/sgcpd/src/worker_boot_disk_resize.sh &

while true; do
	# check if Podman is responsive
	if ! timeout 300 podman info &> /dev/null; then
		echo "`date` podman flatlined"
		scontrol update nodename=$HOSTNAME state=FAIL reason="podman flatlined" && \
		gcloud compute instances delete $HOSTNAME --zone $ZONE --quiet
	fi

	# check if disk is full (<5% space remaining on root partition)
	if ! df / | awk 'NR == 2 { if($4/($4 + $3) < 0.05) { exit 1 } }'; then
		echo "`date` local disk full"
		scontrol update nodename=$HOSTNAME state=FAIL reason="local disk full" && \
		gcloud compute instances delete $HOSTNAME --zone $ZONE --quiet
	fi

	# check if this node had problems attaching a disk (as reported by a task's
	# localization script)
	if [ -f /.fatal_disk_issue_sentinel ]; then
		echo "`date` fatal disk issue"
		scontrol update nodename=$HOSTNAME state=FAIL reason="disk attach problems" && \
		gcloud compute instances delete $HOSTNAME --zone $ZONE --quiet
	fi

	# check if controller is responding; self-destruct if not
	timeout 30 bash -c 'scontrol ping | grep -q "is DOWN"'
	RC=$?
	if [[ $RC == 124 || $RC == 0 ]]; then # 124 -> timeout; 0 -> grep succeeded
		timeout 1 bash -c "echo \"`date` self-destructing due to nonresponsive controller\""
		gcloud compute instances delete $HOSTNAME --zone $ZONE --quiet
	fi

	sleep 300
done
