# this file is meant to be sourced from the Docker entrypoints, and should not be
# run as a standalone.
groupadd -g $(id -g) $HOST_USER && adduser --gid $(id -g) -u $(id -u) --gecos "" --disabled-password $HOST_USER
