#!/usr/bin/env python

import pandas as pd
import numpy as np
import os
import socket
import sys
import subprocess
import pickle
import re

# load node machine type lookup table
node_LuT = pd.read_pickle("/mnt/nfs/clust_conf/slurm/host_LuT.pickle")

# load Canine backend configuration
with open("/mnt/nfs/clust_conf/canine/backend_conf.pickle", "rb") as f:
	k9_backend_conf = pickle.load(f)
default_preemptible_flag = k9_backend_conf['preemptible'] # this is '--preemptible' or ''

# for some reason, the USER environment variable is set to root when this
# script is run, even though it's run under user slurm ...
os.environ["USER"] = "slurm"

# export gcloud credential path
os.environ["CLOUDSDK_CONFIG"] = "/slurm_gcloud_config"

# get list of nodenames to create
hosts = subprocess.check_output("scontrol show hostnames {}".format(sys.argv[1]), shell = True).decode().rstrip().split("\n")

# For preemptible partition, partition name is same as machine type.
# For nonpreemptible partition, partition_name == machine_type + "-nonp"
def map_partition_machinetype(partition):
	if partition.endswith("-nonp"):
		return partition[:-len("-nonp")]
	elif "-nonp-" in partition:
		return partition.split("-nonp-")[0]
	else:
		return partition

# increase disk size so that: 1. match disk io with network io; 2. allow workloads that
# put intermediate files to /tmp.
# TODO: handle this in Canine via scratch disk, mount /tmp there
# TODO: dynamically resize disk to accommodate large docker pulls
def map_partition_disksize(partition):
	try:
		ncore = int(re.search("[^-]+-[^-]+-(.*)", partition)[1])
		ans = min(100 + ncore * 50, 500)
	except Exception:
		# fallback
		ans = 100
	return str(ans) + "GB"

# create all the nodes of each machine type at once
# XXX: gcloud assumes that sys.stdin will always be not None, so we need to pass
#      dummy stdin (/dev/null)
for key, host_list in node_LuT.loc[hosts].groupby(["machine_type", "preemptible", "accelerator_count", "accelerator_type"], dropna=False):
	machine_type, not_nonpreemptible_part, acc_count, acc_type = key
	machine_type = map_partition_machinetype(machine_type)
	disk_size = "25GB"

	# override 'preemptible' flag if this node is in the "non-preemptible" partition
	if not not_nonpreemptible_part:
		k9_backend_conf['preemptible'] = ''
	else:
		k9_backend_conf['preemptible'] = default_preemptible_flag

	# set accelerator flags if neccessary
	accelerator_flags = ""
	if isinstance(acc_count, str):
		disk_size = "50GB" # cuda images are heavy, scale up boot disk to accomodate
		acc_count = int(acc_count)
		accelerator_flags = f"--accelerator=count={acc_count},type={acc_type} --maintenance-policy=TERMINATE"

	# Tell the worker which bucket holds the mirrored cluster config, so
	# fetch_cluster_config.sh (run from the worker container entrypoint) can pull
	# it to node-local disk. Read from the backend config canine pickled, which
	# carries storage_bucket only because canine re-dumps it after the bucket is
	# provisioned -- the copy written during init_slurm() has it as None.
	# Omitted entirely when there is no bucket, so the worker falls back to the
	# NFS config copy. See NFS-FUSE-IMPLEMENTATION-PLAN.md phase 2.
	_metadata_kv = []
	_config_bucket = k9_backend_conf.get("storage_bucket")
	if _config_bucket:
		_metadata_kv.append("cluster-config-bucket={}".format(_config_bucket))

	# Name of the Secret Manager secret holding the user's gcloud credentials,
	# fetched at boot by docker_copy_gcloud_credentials.sh. Absent when canine
	# could not publish it, in which case the worker uses the NFS copy.
	_creds_secret = k9_backend_conf.get("credentials_secret")
	if _creds_secret:
		_metadata_kv.append("credentials-secret={}".format(_creds_secret))

	extra_metadata = "--metadata " + ",".join(_metadata_kv) if _metadata_kv else ""

	# Workers need cloud-platform to reach Secret Manager. GCE's default scopes
	# do not include it, and this has been invisible until now because every
	# gcloud call on a worker runs as the *user* via CLOUDSDK_CONFIG
	# (container_heartbeat.sh, slurm_suspend.sh) rather than as the service
	# account. The credential fetch is the one call that must use the SA,
	# because it runs before user credentials exist on the node.
	scopes_flag = "--scopes=cloud-platform" if _creds_secret else ""

	# run gcloud command to create instances
	subprocess.run(
	  """/sgcpd/slurm_gcp_docker/docker_bin/gcloud_exp_backoff 320 compute instances create {HOST_LIST} --image {image} --image-project {image_project} \
		 --machine-type {MT} \
         --metadata-from-file startup-script=/sgcpd/slurm_gcp_docker/worker_startup_script.sh,shutdown-script=/sgcpd/slurm_gcp_docker/worker_shutdown_script.sh \
         {EXTRA_METADATA} {SCOPES} \
         --zone {compute_zone} {preemptible} \
		 --boot-disk-size {DISK_SIZE} {ACCELERATOR_FLAGS} \
		 --tags caninetransientimage
	  """.format(
		HOST_LIST = " ".join(host_list.index), MT = machine_type, DISK_SIZE = disk_size,
		ACCELERATOR_FLAGS = accelerator_flags, EXTRA_METADATA = extra_metadata,
		SCOPES = scopes_flag,
		**k9_backend_conf
	  ), shell = True, executable = '/bin/bash', stdin = subprocess.DEVNULL
	)
