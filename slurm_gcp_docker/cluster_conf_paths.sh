#
# Resolve where this node reads its Slurm/canine configuration from.
# Meant to be sourced, not executed.
#
# Preference order:
#   1. /opt/cluster-conf  -- node-local, fetched from GCS by fetch_cluster_config.sh
#   2. /mnt/nfs/clust_conf -- the shared NFS mount (today's authoritative copy)
#
# The NFS fallback is deliberate and load-bearing for now. This is the reader
# half of moving cluster config off the shared mount
# (NFS-FUSE-IMPLEMENTATION-PLAN.md phase 2); the writer still populates
# /mnt/nfs/clust_conf, and canine additionally mirrors it to GCS. Preferring the
# local copy exercises the new path on every boot, while the fallback means a
# failed or absent fetch degrades to exactly today's behaviour rather than
# hanging the cluster.
#
# That matters more than it looks: slurm_start.sh blocks in a `while [ ! -f ]`
# loop waiting for slurm.conf. A wrong path there does not error, it hangs
# startup silently forever.
#
# Once NFS is retired (phase 6/7) the fallback branch is deleted and
# /opt/cluster-conf becomes the only source.

CLUSTER_CONF_LOCAL_DIR="${CLUSTER_CONF_LOCAL_DIR:-/opt/cluster-conf}"
CLUSTER_CONF_NFS_DIR="${CLUSTER_CONF_NFS_DIR:-/mnt/nfs/clust_conf}"

# Echo the config dir that currently holds slurm.conf, or nothing if neither does.
resolve_cluster_conf_dir() {
	if [ -f "${CLUSTER_CONF_LOCAL_DIR}/slurm/slurm.conf" ]; then
		echo "${CLUSTER_CONF_LOCAL_DIR}"
	elif [ -f "${CLUSTER_CONF_NFS_DIR}/slurm/slurm.conf" ]; then
		echo "${CLUSTER_CONF_NFS_DIR}"
	fi
}

# Block until slurm.conf appears in either location, then export SLURM_CONF.
# Optional arg: seconds to wait before giving up (default: wait forever, which
# is the pre-existing behaviour).
wait_for_slurm_conf() {
	local timeout="${1:-0}" waited=0 dir=""
	while : ; do
		dir="$(resolve_cluster_conf_dir)"
		[ -n "$dir" ] && break
		if [ "$timeout" -gt 0 ] && [ "$waited" -ge "$timeout" ]; then
			echo "ERROR: no slurm.conf in ${CLUSTER_CONF_LOCAL_DIR} or ${CLUSTER_CONF_NFS_DIR} after ${timeout}s" >&2
			return 1
		fi
		echo -n "."
		sleep 1
		waited=$((waited + 1))
	done
	export SLURM_CONF="${dir}/slurm/slurm.conf"
	export CLUSTER_CONF_DIR="${dir}"
	return 0
}
