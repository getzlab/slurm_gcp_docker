#!/bin/bash

# uncomment for logging (to debug resume script)
/sgcpd/slurm_gcp_docker/slurm_suspend.sh $@ &> /dev/null # &> /mnt/nfs/suspend_log.txt
