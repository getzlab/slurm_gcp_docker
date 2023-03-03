#!/bin/bash

# uncomment for logging (to debug resume script)
/sgcpd/src/slurm_suspend.sh $@ &> /dev/null # &> /mnt/nfs/suspend_log.txt
