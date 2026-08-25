#!/bin/bash

# runs inside each worker container, checks every 5 minutes if the container is
# healthy. if not, blacklist this node.

export CLOUDSDK_CONFIG=/slurm_gcloud_config

# add exponential backoff to all gcloud commands
shopt -s expand_aliases
alias gcloud=gcloud_exp_backoff

# Instance logfile, node-local.
#
# This was /mnt/nfs/clust_logs/${HOSTNAME}.heartbeat.log. The `exec` below opens
# the file once -- O_TRUNC, since it is `>` and not `>>` -- and holds that one fd
# for the entire life of the VM. That is the write pattern gcsfuse cannot
# support, so it has to come off the shared mount
# (NFS-FUSE-IMPLEMENTATION-PLAN.md phase 3).
#
# Nothing ever read it, in any repo or anywhere in git history. The only other
# reference was provision_server.py, which *deleted* the directory's contents at
# cluster start -- and since worker hostnames are statically recycled, the
# previous occupant's log was clobbered by line 25 anyway. It was never an
# archive, so nothing is lost by making it node-local.
#
# Note this captures more than the loop below -- hung_disk_daemon.py and
# worker_boot_disk_resize.sh are backgrounded after the exec and inherit the
# redirection, and both do write. That is preserved; they just land on local
# disk now.
export LOGFILE=/var/log/wolf_heartbeat.log
[ -f $LOGFILE ] && rm -f $LOGFILE
exec > $LOGFILE 2>&1

# get zone of instance
ZONE=$(basename $(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone 2> /dev/null))

# Project this VM lives in, for report_terminal below.
#
# Taken from the metadata server rather than left to gcloud's config. gcloud
# here runs against CLOUDSDK_CONFIG=/slurm_gcloud_config, whose core/project is
# whatever the *user's* workstation had when their credentials were packed into
# the Secret Manager payload -- canine lets config["project"] differ from that,
# and a user with no project set at all would make the write fail outright.
# Either way the failure is silent, since report_terminal ends in `|| true`.
# The metadata server always names the project the instance is actually in,
# which is where a log about this instance belongs. Same trap as the
# `gcloud secrets update` project mismatch fixed in credentials_keepalive.sh.
PROJECT=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id 2> /dev/null)
PROJECT_FLAG=""
[ -n "$PROJECT" ] && PROJECT_FLAG="--project=$PROJECT"

# Record a terminal condition somewhere that outlives this VM.
#
# Every caller below deletes the instance moments later, so $LOGFILE -- now on
# the node's own disk -- dies with the evidence. Cloud Logging is the only
# channel that survives the node. (It was already lost before this change: the
# NFS copy was wiped by provision_server.py:82 on the next cluster start.)
#
# Best-effort and time-boxed on purpose. This runs on the path to
# self-destruction; a hung or unauthorized log write must not stop a broken node
# from tearing itself down. The original code wrapped its NFS write in
# `timeout 1` out of the same concern -- that a write to a dead mount would
# block forever -- and the concern still applies to a network call.
#
# `timeout 30 gcloud` deliberately bypasses the gcloud_exp_backoff alias above:
# bash only alias-expands the first word of a command, so this runs the real
# binary. Retrying is wrong here -- we are racing the node's own deletion.
report_terminal() {
	local reason="$1"
	echo "`date` ${reason}"
	timeout 30 gcloud logging write wolf_worker_heartbeat \
	  "{\"host\": \"${HOSTNAME}\", \"zone\": \"${ZONE}\", \"reason\": \"${reason}\"}" \
	  $PROJECT_FLAG --payload-type=json --severity=ERROR &> /dev/null || true
}

# run separate daemon to detect hung disks
/sgcpd/slurm_gcp_docker/hung_disk_daemon.py &

# run separate daemon to automatically resize boot disk
/sgcpd/slurm_gcp_docker/worker_boot_disk_resize.sh &

while true; do
	# check if Podman is responsive
	if ! timeout 300 podman info &> /dev/null; then
		report_terminal "podman flatlined"
		scontrol update nodename=$HOSTNAME state=FAIL reason="podman flatlined" && \
		gcloud compute instances delete $HOSTNAME --zone $ZONE --quiet
	fi

	# check if disk is full (<5% space remaining on root partition)
	#
	# Note this branch now writes its local diagnostic to the very disk it has
	# just declared full, so that echo may be the one that fails. It does not
	# matter: report_terminal's Cloud Logging call is the durable record, and it
	# does not touch local disk.
	if ! df / | awk 'NR == 2 { if($4/($4 + $3) < 0.05) { exit 1 } }'; then
		report_terminal "local disk full"
		scontrol update nodename=$HOSTNAME state=FAIL reason="local disk full" && \
		gcloud compute instances delete $HOSTNAME --zone $ZONE --quiet
	fi

	# check if this node had problems attaching a disk (as reported by a task's
	# localization script)
	if [ -f /.fatal_disk_issue_sentinel ]; then
		report_terminal "fatal disk issue"
		scontrol update nodename=$HOSTNAME state=FAIL reason="disk attach problems" && \
		gcloud compute instances delete $HOSTNAME --zone $ZONE --quiet
	fi

	# check if controller is responding; self-destruct if not
	timeout 30 bash -c 'scontrol ping | grep -q "is DOWN"'
	RC=$?
	if [[ $RC == 124 || $RC == 0 ]]; then # 124 -> timeout; 0 -> grep succeeded
		report_terminal "self-destructing due to nonresponsive controller"
		gcloud compute instances delete $HOSTNAME --zone $ZONE --quiet
	fi

	sleep 300
done
