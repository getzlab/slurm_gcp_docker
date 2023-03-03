# this file is meant to be sourced from the Docker entrypoints, and should not be
# run as a standalone.
groupadd -g $HOST_GID $HOST_USER && adduser --gid $HOST_GID -u $HOST_UID --gecos "" --disabled-password $HOST_USER
