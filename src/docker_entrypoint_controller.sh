#!/bin/bash

. /sgcpd/src/docker_init_credentials.sh

. /gcsdk/google-cloud-sdk/path.bash.inc

/sgcpd/src/docker_copy_gcloud_credentials.sh

mysqld --user root &
sudo -E -u $HOST_USER /sgcpd/src/provision_server.py
sudo -E -u $HOST_USER /bin/bash
