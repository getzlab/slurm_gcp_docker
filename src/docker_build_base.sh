#!/bin/bash

# This builds the base container image. This is only for developers adding new
# features to the Slurm GCP Docker image.

# note that the Docker daemon must have experimental features enabled;
# add { "experimental": true } to /etc/docker/daemon.json

VERSION=$(cat VERSION)
(cd .. &&
sudo docker build --squash -t broadinstitute/slurm_gcp_docker_base:$VERSION \
  -t broadinstitute/slurm_gcp_docker_base:latest \
  -f src/Dockerfile_base .)

# This can then be pushed to a container repo, e.g. gcr.io:
#
# docker tag broadinstitute/slurm_gcp_docker_base:$VERSION \
#   gcr.io/broad-getzlab-workflows/slurm_gcp_docker_base:$VERSION
# docker tag broadinstitute/slurm_gcp_docker_base:$VERSION \
#   gcr.io/broad-getzlab-workflows/slurm_gcp_docker_base:latest
# docker push gcr.io/broad-getzlab-workflows/slurm_gcp_docker_base:$VERSION
# docker push gcr.io/broad-getzlab-workflows/slurm_gcp_docker_base:latest
