#
# this file is meant to be sourced from other scripts, and should not be run
# as a standalone.

export SLURM_CONF=/mnt/nfs/clust_conf/slurm/slurm.conf

echo -n "Waiting for Slurm configuration ..."
while [ ! -f $SLURM_CONF ]; do
	echo -n "."
	sleep 1
done
echo

sudo munged -f
sudo -E slurmd -f $SLURM_CONF
