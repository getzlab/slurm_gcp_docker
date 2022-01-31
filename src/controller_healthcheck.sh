#!/bin/bash

while true; do 
    # kill all running hosts that slurm thinks are "down"
    sinfo --format %N -t down -Nh -p all | grep -Fx -f - <(gcloud compute instances list --format="csv(name)") | xargs gcloud compute instances delete

    # resume all down hosts
    scontrol update nodename=$(sinfo -h --format %N -t down -p all) state=resume

    # increase disk size
    # cannot have partitions
    # TODO

    # check for resource contraints; pause jobs
    # TODO

    sleep 600
done
