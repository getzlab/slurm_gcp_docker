#!/bin/bash

# Grows this worker's boot disk, its root partition and its filesystem as the
# filesystem fills (podman images accumulate there across jobs). Runs inside the
# slurm container, started by container_heartbeat.sh, whose log gets its output.

log() { echo "`date` boot disk resize: $*"; }

ZONE=$(basename $(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone 2> /dev/null))

# The host's root partition, by device number. Not a name: the boot disk is
# /dev/sda on SCSI machine types but /dev/nvme0n1 on NVMe ones (N4, C3, ...), and
# assuming /dev/sda left every NVMe worker's filesystem at its initial size while
# the GCE disk under it was grown again and again. /proc/1 is the host's init (the
# container shares the host's PID namespace), and /sys names the partition, its
# disk and its partition number.
MAJMIN=$(awk '$5 == "/" { print $3; exit }' /proc/1/mountinfo)
SYSPART=$(readlink -f /sys/dev/block/$MAJMIN 2> /dev/null)
if [[ -z $MAJMIN || ! -f $SYSPART/partition ]]; then
	log "cannot find the root partition (device '$MAJMIN'); not resizing"
	exit 1
fi
PART=$(basename $SYSPART)
DISK=$(basename $(dirname $SYSPART))
PARTNUM=$(cat $SYSPART/partition)
log "watching /dev/$PART (partition $PARTNUM of /dev/$DISK)"

# sizes in GiB, from the kernel: /sys counts 512-byte sectors
disk_gb() { echo $(( $(cat /sys/block/$DISK/size) / 2097152 )); }
part_gb() { echo $(( $(cat /sys/block/$DISK/$PART/size) / 2097152 )); }

grow_filesystem() {
	# growpart exits 1 with NOCHANGE when there is nothing to grow
	sudo growpart /dev/$DISK $PARTNUM
	sudo resize2fs /dev/$PART && log "filesystem now $(df -h --output=size / | tail -1 | tr -d ' ')"
}

while true; do
	sleep 10
	FS_GB=$(df -B1G / | awk 'NR == 2 { print int($3 + $4) }')
	FREE_GB=$(df -B1G / | awk 'NR == 2 { print int($4) }')
	[[ $((100*FREE_GB/FS_GB)) -lt 30 ]] || continue

	# The disk may already be larger than the partition: a resize that the
	# partition or filesystem did not follow. Grow into it before asking GCE for more.
	if [[ $(disk_gb) -gt $(( $(part_gb) + 1 )) ]]; then
		log "disk is $(disk_gb)G but /dev/$PART is $(part_gb)G; growing into it"
		grow_filesystem
		continue
	fi

	# Based on the disk's own size, not the filesystem's: GCE refuses a size that is
	# not larger than the disk.
	NEW_GB=$(( $(disk_gb)*160/100 ))
	log "${FREE_GB}G of ${FS_GB}G free; resizing the disk from $(disk_gb)G to ${NEW_GB}G"
	if ! gcloud_exp_backoff 320 compute disks resize $HOSTNAME --quiet --zone $ZONE --size $NEW_GB; then
		# GCE rate-limits disk resizes; retrying every 10 s only prolongs it
		log "disk resize failed; retrying in 60 s"
		sleep 60
		continue
	fi
	# wait for the kernel to see the new size
	for i in $(seq 30); do
		[[ $(disk_gb) -ge $NEW_GB ]] && break
		sleep 2
	done
	grow_filesystem
done
