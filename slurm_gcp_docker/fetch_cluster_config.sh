#!/bin/bash
#
# Pull the cluster's Slurm/canine configuration from GCS to node-local disk.
#
# This is the download half of moving cluster config off the shared NFS mount
# (NFS-FUSE-IMPLEMENTATION-PLAN.md phase 2). canine mirrors /mnt/nfs/clust_conf
# into gs://<bucket>/_cluster_conf/ at cluster startup
# (canine/utils.py:upload_cluster_config).
#
# Called from docker_entrypoint_worker.sh, before slurm_start.sh. slurm_start.sh
# prefers $DEST over the NFS copy (cluster_conf_paths.sh), so a failure here is
# non-fatal by design and degrades to the pre-existing behaviour. slurm_resume.py
# still reads /mnt/nfs/clust_conf directly, but it only ever runs on the
# controller, where that path is local.
#
# Note on slurmdbd.conf: it is NOT distributed through here, and does not need
# to be. slurmdbd runs only on the controller (provision_server.py:200 -- the
# worker entrypoint starts slurmd only), the controller regenerates the file
# locally on every cluster start, and it is written 0600 owned by `slurm`,
# which is why the upload side excludes it (canine utils.upload_cluster_config).
# An earlier version of this script chmod'd/chown'd a fetched copy; that was
# solving a distribution problem that does not exist.
#
# Usage:  fetch_cluster_config.sh [<bucket>] [<dest-dir>] [<prefix>]
#
# Bucket and prefix are each resolved in this order:
#   1. positional argument
#   2. $CLUSTER_CONFIG_BUCKET / $CLUSTER_CONFIG_PREFIX
#   3. GCE instance metadata "cluster-config-bucket" / "cluster-config-prefix"
#
# Exits non-zero on failure. Callers wiring this into boot MUST treat failure
# as non-fatal while the NFS copy is still authoritative.

set -uo pipefail

DEST="${2:-/opt/cluster-conf}"

metadata_attr() {
	curl -s -f -H "Metadata-Flavor: Google" \
	  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1" 2>/dev/null
}

resolve_bucket() {
	if [[ -n "${1:-}" ]]; then echo "$1"; return 0; fi
	if [[ -n "${CLUSTER_CONFIG_BUCKET:-}" ]]; then echo "$CLUSTER_CONFIG_BUCKET"; return 0; fi
	metadata_attr cluster-config-bucket && return 0
	return 1
}

# The object prefix, which canine namespaces per controller VM
# (canine.utils.cluster_config_prefix) because one bucket is shared by every
# cluster in the project. Falling back to the bare prefix would read whichever
# controller wrote last, so only do that when nothing tells us otherwise --
# which means an older canine, whose mirror was unnamespaced anyway.
resolve_prefix() {
	if [[ -n "${3:-}" ]]; then echo "$3"; return 0; fi
	if [[ -n "${CLUSTER_CONFIG_PREFIX:-}" ]]; then echo "$CLUSTER_CONFIG_PREFIX"; return 0; fi
	metadata_attr cluster-config-prefix && return 0
	echo "_cluster_conf"
}

BUCKET="$(resolve_bucket "${1:-}")"
PREFIX="$(resolve_prefix "${1:-}" "${2:-}" "${3:-}")"
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

# Defensive only: slurmdbd.conf is excluded on the upload side and should never
# appear here. If a stale copy from an older mirror does turn up, secure it
# rather than leave a 0644 credentials-bearing file on disk.
if [[ -f "$DEST/slurm/slurmdbd.conf" ]]; then
	chmod 600 "$DEST/slurm/slurmdbd.conf" || true
	id slurm &>/dev/null && chown slurm: "$DEST/slurm/slurmdbd.conf" || true
	echo "fetch_cluster_config: WARNING - unexpected slurmdbd.conf in mirror; secured it" >&2
fi

echo "fetch_cluster_config: fetched $(find "$DEST" -type f | wc -l) file(s)"
find "$DEST" -type f -printf '  %P\n' 2>/dev/null | sort
