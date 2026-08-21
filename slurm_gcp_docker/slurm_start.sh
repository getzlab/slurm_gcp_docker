#
# this file is meant to be sourced from other scripts, and should not be run
# as a standalone.

# Resolve SLURM_CONF from node-local config if present, else the NFS mount.
# See cluster_conf_paths.sh for why the fallback exists.
. /sgcpd/slurm_gcp_docker/cluster_conf_paths.sh

echo -n "Waiting for Slurm configuration ..."
wait_for_slurm_conf
echo
echo "Using SLURM_CONF=${SLURM_CONF}"

sudo munged -f
sudo -E slurmd -f $SLURM_CONF
