# resolves occasional quota exceeded error, per https://stackoverflow.com/questions/54405454/error-response-from-daemon-join-session-keyring-create-session-key-disk-quota
# these values come from root_max{keys,bytes}
echo 1000000 > /proc/sys/kernel/keys/maxkeys
echo 25000000 > /proc/sys/kernel/keys/maxbytes

# only set gpu flags if gpu is attached
nvidia-smi && GPU_FLAGS="--gpus all"

# start the container
docker run -dti --rm --pid host --network host --privileged \
  -v /mnt/nfs:/mnt/nfs -v /sys/fs/cgroup:/sys/fs/cgroup \
  -v /var/run/docker.sock:/var/run/docker.sock -v /usr/bin/docker:/usr/bin/docker \
  -v /etc/gcloud:/etc/gcloud -v /dev:/dev ${GPU_FLAGS} \
  --entrypoint /usr/local/share/slurm_gcp_docker/src/docker_entrypoint_worker.sh --name slurm \
  broadinstitute/slurm_gcp_docker
