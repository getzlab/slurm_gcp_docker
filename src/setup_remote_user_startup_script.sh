#!/usr/bin/env bash

set -x

cd ~

if ! [ -f /.startup ]; then
    ## dependencies
    set -e

    ## OS-login will map the user to a specific GID, however in ubuntu it didn't actually create the group.
    sudo groupadd -g `id -g` `whoami`

    sudo apt-get -qq update
    sudo apt-get -qq -y install nfs-common docker.io python3-pip nfs-kernel-server git
    sudo pip3 install docker-compose google-crc32c

    echo '* hard nofile 6400' | sudo tee -a /etc/security/limits.conf > /dev/null
    echo '* soft nofile 6400' | sudo tee -a /etc/security/limits.conf > /dev/null

    sudo groupadd docker || true
    sudo usermod -aG docker $USER

    ## enable docker experimental features
    echo '{"experimental": true}' | sudo tee -a /etc/docker/daemon.json > /dev/null
    sudo systemctl restart docker

    sudo chmod 777 /var/run/docker.sock ## won't work after reboot

    ## jupyter notebook
    sudo apt-get -qq -y install jupyter

    ## wolf
    chmod 400 ~/slurm_gcp_docker/getzlabkey
    GIT_SSH_COMMAND='ssh -i ~/slurm_gcp_docker/getzlabkey -o IdentitiesOnly=yes -o StrictHostKeyChecking=no' git clone git@github.com:getzlab/wolF.git ~/wolF
    GIT_SSH_COMMAND='ssh -i ~/slurm_gcp_docker/getzlabkey -o IdentitiesOnly=yes -o StrictHostKeyChecking=no' git clone git@github.com:getzlab/canine.git ~/canine

    (cd ~/canine && git checkout master && sudo pip3 install .)
    (cd ~/wolF && git checkout master && sudo pip3 install .)

    cp -r ~/wolF/examples ~/examples

    ## auth ssh key
    mkdir -p ~/.ssh
    cat ~/slurm_gcp_docker/getzlabkey.pub >> ~/.ssh/authorized_keys

    ## systemd user units will stop after log-out, this avoids that.
    sudo loginctl enable-linger $USER

    ## install systemd units
    (cd ~/slurm_gcp_docker/src && python3 install_service.py)

    ## start prefect server and jupyter notebook
    sudo systemctl start prefectserver          # port 8080 and 4200
    sudo systemctl enable prefectserver
    systemctl start --user jupyternotebook # port 8888
    systemctl enable --user jupyternotebook

    ## vs code
    curl -fsSL https://code-server.dev/install.sh | sh
    mkdir -p ~/.config/code-server
    echo 'bind-addr: 127.0.0.1:8889' > ~/.config/code-server/config.yaml
    echo 'auth: none'                >> ~/.config/code-server/config.yaml
    echo 'cert: false'               >> ~/.config/code-server/config.yaml

    sudo systemctl enable --now code-server@$USER

    set +e
fi

sudo touch /.startup
