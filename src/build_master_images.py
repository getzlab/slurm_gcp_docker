#!/usr/bin/env python3

import argparse
import os
import socket
import subprocess
import sys
import shlex
import tempfile

from setup_local import check_gcloud_auth, check_docker, error

def parse_args(zone, project):
	parser = argparse.ArgumentParser(description =
"""
This builds the master Slurm Docker image and worker VM host image.
This is only used by developers updating core functionality of this software package.

Note that the Docker daemon must have experimental features enabled;
add { "experimental": true } to /etc/docker/daemon.json
""", formatter_class = argparse.RawTextHelpFormatter)
	parser.add_argument('--imagename', '-i', help = "Name of image to create", required = True)
	parser.add_argument('--zone', '-z', help = "Compute zone to create dummy instance in", default = zone)
	parser.add_argument('--project', '-p', help = "Compute project to create image in", default = project)
	parser.add_argument('--dummyhost', '-d', help = "Name of dummy VM image gets built on", default = "dummyhost")
	parser.add_argument('--build_script', '-s', help = "Path to build script whose output is run on the dummy VM", default = "./container_host_image_startup_script.sh")
	parser.add_argument('--image_family', '-f', help = "Family to add image to", default = "slurm-gcp-docker")
	parser.add_argument('--push_images', help = "Whether to push images to centeralized container regisitry/GCP project", action = "store_true")
	parser.add_argument('--skip_vm_image_build', help = "Skip building the worker VM image, i.e. only build the Docker image", action = "store_true")

	args = parser.parse_args()

	# TODO: check args

	# validate zone
	# if ! grep -qE '(asia|australia|europe|northamerica|southamerica|us)-[a-z]+\d+-[a-z]' <<< "$ZONE"; then
	# 	echo "Error: invalid zone"
	# 	exit 1
	# fi

	return args

if __name__ == "__main__":
	#
	# check prerequisites
	check_gcloud_auth()
	check_docker()
	try:
		subprocess.check_call("[ -f /etc/docker/daemon.json ] && grep -Eq 'experimental.*[Tt]rue' /etc/docker/daemon.json", shell = True)
	except subprocess.CalledProcessError:
		error('Experimental mode must be enabled in Docker (add { "experimental": true } to /etc/docker/daemon.json and restart Docker service)')

	#
	# get zone of current instance
	default_zone = subprocess.check_output(
		"curl -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/zone", shell=True, stderr = subprocess.DEVNULL
	).decode().rstrip()
	default_zone = default_zone.split("/")[-1]

	#
	# get current project (if any)
	default_proj = subprocess.check_output(
		'curl "http://metadata.google.internal/computeMetadata/v1/project/project-id" -H "Metadata-Flavor: Google"', shell=True, stderr = subprocess.DEVNULL
	).decode().rstrip()

	#
	# parse arguments
	args = parse_args(default_zone, default_proj)
	zone = args.zone
	proj = args.project
	imagename = args.imagename

	#
	# get hostname
	host = args.dummyhost + "-" + os.environ["USER"]

	#
	# 1. build Docker image
	#

	VERSION = open("VERSION").read().rstrip()

	subprocess.check_call(f"""
	  (cd .. &&
	  sudo docker build --squash -t broadinstitute/slurm_gcp_docker:{VERSION} \
		-t broadinstitute/slurm_gcp_docker:latest \
		-f src/Dockerfile .)""", shell = True
	)

	if args.push_images:
		subprocess.check_call(f"""
		  docker tag broadinstitute/slurm_gcp_docker:{VERSION} \
			gcr.io/broad-getzlab-workflows/slurm_gcp_docker:{VERSION} && \
		  docker tag broadinstitute/slurm_gcp_docker:{VERSION} \
			gcr.io/broad-getzlab-workflows/slurm_gcp_docker:latest && \
		  docker push gcr.io/broad-getzlab-workflows/slurm_gcp_docker:{VERSION} && \
		  docker push gcr.io/broad-getzlab-workflows/slurm_gcp_docker:latest""",
		  shell = True
		)

	#
	# 2. build VM worker image
	# 

	if args.skip_vm_image_build:
		sys.exit(0)

	#
	# create dummy instance to build image in
	try:
		subprocess.check_call("""gcloud compute --project {proj} instances create {host} --zone {zone} \
		  --machine-type n1-standard-1 --image ubuntu-minimal-2204-jammy-v20221018 \
		  --image-project ubuntu-os-cloud --boot-disk-size 15GB --boot-disk-type pd-standard \
		  --metadata-from-file startup-script=<({build_script})""".format(
			host = host, proj = proj, zone = zone, build_script = args.build_script
		), shell = True, executable = "/bin/bash")

		#
		# wait for instance to be ready
		subprocess.check_call("""
		  echo -n "Waiting for dummy instance to be ready ..."
		  while ! gcloud compute ssh {host} --zone {zone} -- -o "UserKnownHostsFile /dev/null" \
		    "[ -f /started ]" &> /dev/null; do
			  sleep 1
			  echo -n ".";
		  done
		  echo""".format(host = host, zone = zone),
		  shell = True, executable = "/bin/bash"
		)

		#
		# transfer Slurm Docker image to instance
		print("Transfering slurm docker image to dummy host ...")

		tmp = tempfile.mktemp()
		subprocess.check_call("sudo docker save broadinstitute/slurm_gcp_docker:{} > {}".format(VERSION, tmp), shell=True)
		subprocess.check_call('gcloud compute scp {src} {host}:/tmp/tmp_docker_file --zone {zone} && gcloud compute ssh {host} --zone {zone} -- -o "UserKnownHostsFile /dev/null" sudo touch /data_transferred'.format(src=tmp, host=host, zone=zone), shell=True)
		os.remove(tmp)

		#
		# wait for startup script to be completed
		subprocess.check_call("""
		  echo -n "Waiting for dummy instance to complete startup script ..."
		  while ! gcloud compute ssh {host} --zone {zone} -- -o "UserKnownHostsFile /dev/null" \
		    "[ -f /completed ]" &> /dev/null; do
			  sleep 1
			  echo -n ".";
		  done
		  echo""".format(host = host, zone = zone),
		  shell = True, executable = "/bin/bash"
		)

		#
		# shut down dummy instance
		# (this is to avoid disk caching problems that can arise from imaging a running
		# instance)
		subprocess.check_call(
		  "gcloud compute instances stop {host} --zone {zone} --quiet".format(host = host, zone = zone),
		  shell = True
		)

		#
		# clone base image from dummy host's drive
		try:
			print("Snapshotting dummy host drive ...")
			subprocess.check_call(
			  "gcloud compute disks snapshot {host} --snapshot-names {host}-snap --zone {zone}".format(host = host, zone = zone),
			  shell = True
			)

			print("Creating image from snapshot ...")
			# TODO: add check here to only try and delete the image if it already exists
			try:
				subprocess.check_call("gcloud compute images delete --quiet {imagename}".format(imagename = imagename), shell = True, stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
			except subprocess.CalledProcessError:
				pass
			subprocess.check_call(
			  "gcloud compute images create {imagename} --source-snapshot={host}-snap --family {image_family}-$USER".format(imagename = imagename, host = host, image_family = args.image_family),
			  shell = True
			)

			# TODO: move image to central project accessible to all
			if args.push_images:
				pass
		finally:
			print("Deleting snapshot ...")
			subprocess.check_call("gcloud compute snapshots delete {}-snap --quiet".format(host), shell = True)

	#
	# delete dummy host
	finally:
		print("Deleting dummy host ...")
		subprocess.check_call(
		  "gcloud compute instances delete {host} --zone {zone} --quiet".format(host = host, zone = zone),
		  shell = True
		)
