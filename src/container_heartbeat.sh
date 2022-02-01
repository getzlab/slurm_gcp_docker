#!/bin/bash

# runs inside each worker container, checks every 5 minutes if the container is
# healthy. if not, blacklist this node.

# get zone of instance
ZONE=$(basename $(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone 2> /dev/null))

while true; do
	# check if Podman is responsive
	if ! timeout 30 podman info; then
		scontrol update nodename=$HOSTNAME state=FAIL reason="podman flatlined" && \
		scontrol update nodename=$HOSTNAME state=DOWN reason="podman flatlined" && \
		gcloud compute instances delete $HOSTNAME --zone $ZONE --quiet
	fi

	# check if disk is full (<5% space remaining on root partition)
	if ! df / | awk 'NR == 2 { if($4/($4 + $3) < 0.05) { exit 1 } }'; then
		scontrol update nodename=$HOSTNAME state=FAIL reason="local disk full" && \
		scontrol update nodename=$HOSTNAME state=DOWN reason="local disk full" && \
		gcloud compute instances delete $HOSTNAME --zone $ZONE --quiet
	fi

	sleep 300
done
