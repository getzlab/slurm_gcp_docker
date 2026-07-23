#!/usr/bin/env bash

set -e

VERSION=$(cat VERSION)

## Choose the docker base image to build from:
## 0. (For developer) If specified on the command line, use that.
## 1. (For developer) If broadinstitute/slurm_gcp_docker_base:$VERSION exists locally, use it.
##    This is the local image built by docker_build_base.sh
## 2. Otherwise use gcr.io/broad-getzlab-workflows/slurm_gcp_docker_base:$VERSION

if [ $# == 2 ]; then
	echo "Using base image specified as command line argument: $1:$2"
	docker_base_image=$1
	VERSION=$2
	echo -n $VERSION > VERSION
else
	if sudo docker image inspect broadinstitute/slurm_gcp_docker_base:$VERSION &> /dev/null; then
		echo "Building docker image from broadinstitute/slurm_gcp_docker_base:$VERSION (local)"
		docker_base_image=broadinstitute/slurm_gcp_docker_base
	else
		echo "Building docker image from gcr.io/broad-getzlab-workflows/slurm_gcp_docker_base:$VERSION"
		docker_base_image=gcr.io/broad-getzlab-workflows/slurm_gcp_docker_base
	fi
fi

sudo docker build -t broadinstitute/slurm_gcp_docker:$VERSION \
  -t broadinstitute/slurm_gcp_docker:latest \
  --build-arg HOST_USER=$USER --build-arg UID=$UID --build-arg GID=$(id -g) \
  --build-arg DOCKER_BASE_IMAGE="$docker_base_image":"$VERSION" \
  .

echo -n $docker_base_image > DOCKER_SRC
