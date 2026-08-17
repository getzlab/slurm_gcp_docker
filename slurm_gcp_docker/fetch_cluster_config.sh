#!/bin/bash
#
# Pull the cluster's Slurm/canine configuration from GCS to node-local disk.
#
# This is the download half of moving cluster config off the shared NFS mount
# (NFS-FUSE-IMPLEMENTATION-PLAN.md phase 2). canine mirrors /mnt/nfs/clust_conf
# into gs://<bucket>/_cluster_conf/ at cluster startup
# (canine/utils.py:upload_cluster_config).
#
# STATUS: staged, not yet wired into the boot path. Nothing reads
# $CLUSTER_CONF_DIR yet -- slurm_start.sh, slurm_suspend.sh and slurm_resume.py
# still read /mnt/nfs/clust_conf directly. Retargeting them is deliberately
# deferred until it can be validated against a live cluster, because a mistake
# there stops the cluster from booting at all.
#
# Why this exists separately from the NFS copy: slurmdbd refuses to start
# unless slurmdbd.conf is mode 0600 owned by SlurmUser. gcsfuse has only a
# mount-wide --file-mode and cannot express per-file ownership, so that file
# can never live on a bucket mount. Landing config on local disk resolves that
# outright -- the chmod/chown below are ordinary local-filesystem operations.
#
# Usage:  fetch_cluster_config.sh [<bucket>] [<dest-dir>]
#
# The bucket is resolved in this order:
#   1. $1
#   2. $CLUSTER_CONFIG_BUCKET
#   3. GCE instance metadata attribute "cluster-config-bucket"
#
# Exits non-zero on failure. Callers wiring this into boot MUST treat failure
# as non-fatal while the NFS copy is still authoritative.

set -uo pipefail

DEST="${2:-/opt/cluster-conf}"
PREFIX="_cluster_conf"

resolve_bucket() {
	if [[ -n "${1:-}" ]]; then echo "$1"; return 0; fi
	if [[ -n "${CLUSTER_CONFIG_BUCKET:-}" ]]; then echo "$CLUSTER_CONFIG_BUCKET"; return 0; fi
	curl -s -f -H "Metadata-Flavor: Google" \
	  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/cluster-config-bucket" \
	  2>/dev/null && return 0
	return 1
}

BUCKET="$(resolve_bucket "${1:-}")"
if [[ -z "$BUCKET" ]]; then
	echo "fetch_cluster_config: no bucket given (arg 1, \$CLUSTER_CONFIG_BUCKET, or instance metadata 'cluster-config-bucket')" >&2
	exit 1
fi

SRC="gs://${BUCKET}/${PREFIX}"

echo "fetch_cluster_config: ${SRC} -> ${DEST}"
mkdir -p "$DEST" || { echo "fetch_cluster_config: cannot create $DEST" >&2; exit 1; }

# rsync, not `cp -r`: `gcloud storage cp -r <src>/. <dest>/` does not mean
# "contents of <src>" the way POSIX cp does -- it errors with "matched no
# objects". rsync mirrors the prefix's contents, and is idempotent across the
# repeated boots this sees.
if ! gcloud storage rsync -r "${SRC}" "${DEST}" 2>/tmp/fetch_cluster_config.err; then
	echo "fetch_cluster_config: download failed:" >&2
	cat /tmp/fetch_cluster_config.err >&2
	exit 1
fi

# slurmdbd.conf must be 0600 and owned by SlurmUser or slurmdbd refuses to
# start. This is the specific constraint that makes a bucket mount unusable for
# cluster config and local disk necessary.
if [[ -f "$DEST/slurm/slurmdbd.conf" ]]; then
	chmod 600 "$DEST/slurm/slurmdbd.conf" || true
	if id slurm &>/dev/null; then
		chown slurm: "$DEST/slurm/slurmdbd.conf" || true
	fi
	echo "fetch_cluster_config: secured slurmdbd.conf ($(stat -c '%a %U' "$DEST/slurm/slurmdbd.conf"))"
fi

echo "fetch_cluster_config: fetched $(find "$DEST" -type f | wc -l) file(s)"
find "$DEST" -type f -printf '  %P\n' 2>/dev/null | sort
