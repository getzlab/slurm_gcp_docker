#!/usr/bin/env python3

import argparse
import os
import socket
import subprocess
import sys
import shlex
import tempfile

def parse_args(zone, project):
	parser = argparse.ArgumentParser()
	parser.add_argument('--imagename', '-i', help = "Name of image to create", required = True)
	parser.add_argument('--zone', '-z', help = "Compute zone to create dummy instance in", default = zone)
	parser.add_argument('--project', '-p', help = "Compute project to create image in", default = project)
	parser.add_argument('--dummyhost', '-d', help = "Name of dummy VM image gets built on", default = "dummyhost")
	parser.add_argument('--build_script', '-s', help = "Path to build script whose output is run on the dummy VM", default = "./container_host_image_startup_script.sh")
	parser.add_argument('--dont_copy_gcloud_credentials', '-g', help = "Skip copying of gcloud credentials", action = "store_false", dest = "copy_gcloud_credentials")
	parser.add_argument('--image_family', '-f', help = "Family to add image to", default = "slurm-gcp-docker")

	args = parser.parse_args()

	# TODO: check args

	# validate zone
	# if ! grep -qE '(asia|australia|europe|northamerica|southamerica|us)-[a-z]+\d+-[a-z]' <<< "$ZONE"; then
	# 	echo "Error: invalid zone"
	# 	exit 1
	# fi

	return args

def get_slurm_gcp_docker_root():
	# I placed a marker file ".slurm_gcp_docker_root"
	src_dir = os.path.dirname(__file__)
	src_parent = os.path.abspath(os.path.join(src_dir, os.path.pardir))
	assert os.path.exists(os.path.join(src_parent, ".slurm_gcp_docker_root"))
	return src_parent

if __name__ == "__main__":
	#
	# ensure gcloud is installed
	try:
		subprocess.check_call("[ -f ~/.config/gcloud/config_sentinel ]", shell = True)
	except subprocess.CalledProcessError:
		print("gcloud is not configured. Please run `gcloud auth login` and `gcloud auth application-default login` and try again.", file = sys.stderr)
		sys.exit(1)

	#
	# get zone of current instance
	default_zone = subprocess.check_output(
		"curl -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/zone", shell=True
	).decode().rstrip()
	default_zone = default_zone.split("/")[-1]

	#
	# get current project (if any)
	default_proj = subprocess.check_output(
		'curl "http://metadata.google.internal/computeMetadata/v1/project/project-id" -H "Metadata-Flavor: Google"', shell=True
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
	# create dummy instance to build image in
	try:
		subprocess.check_call("""gcloud compute --project {proj} instances create {host} --zone {zone} \
		  --machine-type n1-standard-1 --image ubuntu-minimal-2004-focal-v20210119a \
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
		# copy gcloud config to instance
		if args.copy_gcloud_credentials:
			print("Copying gcloud credentials to dummy host ...")
			subprocess.check_call("""
			  gcloud compute scp ~/.config/gcloud/* {host}:.config/gcloud --zone {zone} --recurse && \
			  gcloud compute ssh {host} --zone {zone} -- -o "StrictHostKeyChecking no" -o "UserKnownHostsFile /dev/null" -T \
				"sudo cp -r ~/.config/gcloud /etc/gcloud"
			  """.format(host = host, zone = zone),
			  shell = True
			)

		#
		# copy slurm_gcp_docker source to instance and build docker there
		print("Copying slurm_gcp_docker source to dummy host ...")
		subprocess.check_call(
			"gcloud compute scp {src} {host}:/tmp/tmp_slurm_gcp_docker --zone {zone} --recurse".format(
				src=shlex.quote(get_slurm_gcp_docker_root()), host = host, zone = zone
			),
			shell=True
		)

		#
		# transfer docker image there
		print("Transfering slurm docker image to dummy host ...")
		DOCKER_SRC = open("DOCKER_SRC").read().rstrip()
		VERSION = open("VERSION").read().rstrip()

		tmp = tempfile.mktemp()
		subprocess.check_call("sudo docker save {}:{} > {}".format(DOCKER_SRC, VERSION, tmp), shell=True)
		subprocess.check_call("gcloud compute scp {src} {host}:/tmp/tmp_docker_file --zone {zone}".format(src=tmp, host=host, zone=zone), shell=True)
		os.remove(tmp)

		#
		# mark data transferred
		subprocess.check_call(
			'gcloud compute ssh {host} --zone {zone} -- -o "StrictHostKeyChecking no" -o "UserKnownHostsFile /dev/null" -T \
				"sudo cp -r /tmp/tmp_slurm_gcp_docker/ /usr/local/share/slurm_gcp_docker/ && sudo touch /data_transferred"'.format(host = host, zone = zone),
			shell=True
		)

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
