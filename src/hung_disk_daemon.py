#!/usr/bin/env python3

import glob
import os
import requests
import subprocess
import time

PREFIX = "/dev/disk/by-id/google-"
ZONE = os.path.basename(
  requests.get(
    "http://metadata.google.internal/computeMetadata/v1/instance/zone",
    headers = { "Metadata-Flavor" : "Google" }
  ).text
)
HOSTNAME = subprocess.check_output(
  "echo $HOSTNAME",
  shell = True,
  executable = "/bin/bash"
).decode().rstrip()

bad_disks = set()

while True:
    devs = glob.glob(PREFIX + "canine*")
    disknames = [x.lstrip(PREFIX) for x in devs]

    for dev, disk in zip(devs, disknames):
        try:
            mountpoint = subprocess.check_output(f"lsblk -n -o MOUNTPOINT {dev}", shell = True).decode().rstrip()

            # disk is attached and mounted but should have been detached (as indicated by absence of lock)
            # TODO: only do this if disk was confirmed to have been attached for a task (don't interrupt disks in the process of mounting)
            if mountpoint != "" and subprocess.run(f"flock -n {mountpoint} true", shell = True).returncode == 0:
                # second time we've encountered this disk; remove it
                if disk in bad_disks:
                    subprocess.check_call(f"mountpoint -q {mountpoint} && sudo umount {mountpoint} || true", shell = True)
                    subprocess.check_call(f"CLOUDSDK_CONFIG=/mnt/nfs/clust_conf/gcloud gcloud compute instances detach-disk {HOSTNAME} --zone {ZONE} --disk {disk}", shell = True)

                    bad_disks.remove(disk)

                # give disk a second chance, in case it's in the process of being created
                else:
                    bad_disks.add(disk)

            # disk is good now; remove from bad disk set
            else:
                bad_disks.discard(disk)
        except Exception as e:
            print(e)

    time.sleep(30)
