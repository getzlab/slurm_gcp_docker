#!/bin/bash

ZONE=$(basename $(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone 2> /dev/null))

while true; do
  sleep 10
  DISK_SIZE_GB=$(df -B1G / | awk 'NR == 2 { print int($3 + $4) }')
  FREE_SPACE_GB=$(df -B1G / | awk 'NR == 2 { print int($4) }')
  if [[ $((100*FREE_SPACE_GB/DISK_SIZE_GB)) -lt 30 ]]; then
    gcloud_exp_backoff compute disks resize $HOSTNAME --quiet --zone $ZONE --size $((DISK_SIZE_GB*160/100))
    sudo growpart /dev/sda 1
    sudo resize2fs /dev/sda1
  fi
done
