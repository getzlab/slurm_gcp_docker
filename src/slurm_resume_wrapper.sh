#!/bin/bash

# uncomment for logging (to debug resume script)
/sgcpd/src/slurm_resume.py $@ &> /dev/null # &> /mnt/nfs/resume_log.txt
