FROM ubuntu:22.04 as build

WORKDIR /tmp

#
# install Slurm/MySQL/NFS/cluster scripts

# 1. prereqs from apt
RUN apt-get update && \
DEBIAN_FRONTEND=noninteractive \
apt-get -y install --no-install-recommends tzdata && \
apt-get -y install software-properties-common build-essential vim git nfs-common \
  portmap libmariadb-dev mariadb-client mariadb-server munge libmunge-dev \
  libhwloc-dev cgroup-tools libreadline-dev ssed wget sudo curl cloud-guest-utils

# Python 3.8
RUN add-apt-repository -y ppa:deadsnakes/ppa && apt-get update && \
  apt-get install -y python3.8 python3.8-dev python3.8-venv python3.8-distutils && \
  rm -f /usr/bin/python3 && ln -s /usr/bin/python3.8 /usr/bin/python3
# pip
RUN python3 -m ensurepip && python3 -m pip install pip

# 2. convenient symlinks; NFS mount folder
RUN ln -s /usr/bin/python3 /usr/bin/python && \
mkdir -p /mnt/nfs

# 3. build Slurm
RUN wget https://download.schedmd.com/slurm/slurm-20.11.9.tar.bz2 && \
tar xjf slurm-20.11.9.tar.bz2 && \
cd slurm-20.11.9 && \
./configure --prefix=/usr/local --sysconfdir=/usr/local/etc \
  --with-mysql_config=/usr/bin --with-hdf5=no && \
make && make install

# 4. make Slurm directories
RUN adduser -u 1337 --gecos "" --disabled-password slurm && \
mkdir -p /var/spool/slurm && chown slurm:slurm /var/spool/slurm && \
mkdir -p /run/munge

# 5. configure MySQL
RUN mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld && \
(mysqld --user root & while ! mysqladmin -s status; do sleep 1; done ) && \
mysql -u root -e "create user 'slurm'@'localhost'" && \
mysql -u root -e "grant all on slurm_acct_db.* TO 'slurm'@'localhost';"

# 6. set up munge
RUN dd if=/dev/zero bs=1 count=1024 of=/etc/munge/munge.key

# 7. Python prereqs
RUN pip3 install pandas==1.4.2 crcmod google-crc32c requests

# 8. install gcloud and AWS
RUN mkdir /gcsdk && \
wget -O gcs.tgz https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-457.0.0-linux-x86_64.tar.gz && \
tar xzf gcs.tgz -C /gcsdk && \
/gcsdk/google-cloud-sdk/install.sh --usage-reporting false --path-update true --quiet && \
ln -s /gcsdk/google-cloud-sdk/bin/* /usr/bin

RUN apt-get -y install unzip && \
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
  unzip awscliv2.zip && \
  sudo ./aws/install

# 9. get cluster utility scripts
COPY ./src/ /usr/local/share/slurm_gcp_docker/src/
COPY ./conf/ /usr/local/share/slurm_gcp_docker/conf/
RUN ln -s /usr/local/share/slurm_gcp_docker/ /sgcpd
RUN chmod 755 /sgcpd/src/slurm_suspend_wrapper.sh /sgcpd/src/slurm_resume_wrapper.sh

# 10. podman
RUN apt-get install -y libgpgme11 conmon golang-github-containers-common crun
RUN wget -O libsubid4.dpkg https://storage.googleapis.com/getzlab-wolf/libsubid/libsubid4_4.13+dfsg1-1ubuntu1_amd64.deb && \
  dpkg -i libsubid4.dpkg
RUN wget -O podman.dpkg https://storage.googleapis.com/getzlab-wolf/podman/podman_4.3.1.dpkg && \
  dpkg -i podman.dpkg && apt-get install -y fuse-overlayfs iptables

COPY src/podman_conf/*.conf /etc/containers/
COPY src/podman_conf/registries.conf.d/* /etc/containers/registries.conf.d/

# 10.5 get nvidia toolkits for podman
RUN distribution=$(. /etc/os-release;echo $ID$VERSION_ID)  && curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | sudo apt-key add - \
    && curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
RUN sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit

RUN mkdir -p /usr/share/containers/oci/hooks.d/
COPY conf/nvidia_hook_config.txt /usr/share/containers/oci/hooks.d/oci-nvidia-hook.json
RUN sed -i 's/^#no-cgroups = false/no-cgroups = true/;' /etc/nvidia-container-runtime/config.toml

# 11. sudo for all
RUN echo "ALL ALL=(ALL) NOPASSWD: ALL" >>/etc/sudoers

# 12. rclone
RUN wget https://beta.rclone.org/branch/pasnox-symlink/v1.62.0-beta.6680.19c6081de.pasnox-symlink/rclone-v1.62.0-beta.6680.19c6081de.pasnox-symlink-linux-amd64.deb && \
  apt install ./rclone-v1.62.0-beta.6680.19c6081de.pasnox-symlink-linux-amd64.deb

# 13. install wolF (to allow wolFPack to orchestrate workflows on worker nodes)
COPY ./wolF ./wolF
RUN pip3 install ./wolF

#
# clean up /tmp
RUN rm -rf *

#
# clean up packages
RUN apt-get -y remove build-essential vim git && apt-get -y autoremove

#
# set entrypoint
ENTRYPOINT /sgcpd/src/docker_entrypoint_controller.sh

#
# set Slurm/gcloud environment (both paths will be updated via Canine backend)
ENV SLURM_CONF "/mnt/nfs/clust_conf/slurm/slurm.conf"
ENV CLOUDSDK_CONFIG "/user_gcloud_config"

# bind mount gcloud config into task Docker
ENV CANINE_DOCKER_ARGS "-v /user_gcloud_config:/user_gcloud_config"

#
# update PATH environment
ENV PATH="/sgcpd/src/docker_bin:${PATH}"
