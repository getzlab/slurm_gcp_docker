#!/bin/bash

# uncomment for logging (to debug resume script)
/sgcpd/slurm_gcp_docker/slurm_resume.py $@ &> /dev/null # &> /mnt/nfs/resume_log.txt
