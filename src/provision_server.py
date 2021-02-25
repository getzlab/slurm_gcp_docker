#!/usr/bin/python3

import argparse
import io
import os
import tempfile
import json
import pwd
import pandas as pd
import re
import shlex
import socket
import subprocess
# sys.path.append("/home/jhess/j/proj/") # TODO: remove this line when Capy is a package
# from capy import txt

## canine backend config is passed via environments with prefix "BACKEND_CONFIG__"
def parse_canine_conf_from_env():
	config = {}
	for k, v in os.environ.items():
		if k.startswith("BACKEND_CONFIG__"):
			key = k[len("BACKEND_CONFIG__"):]
			config[key] = v
	return config

def parse_slurm_conf(path):
	output = io.StringIO()

	with open(path, "r") as a:
		for line in a:
			if len(line.split("=")) == 2:
				output.write(line)

	output.seek(0)

	return pd.read_csv(output, sep = "=", comment = "#", names = ["key", "value"], index_col = 0, squeeze = True)

# TODO: package Capy so that we don't have to directly source these here
def parsein(X, col, regex, fields):
	T = parse(X[col], regex, fields)
	return pd.concat([X, T], 1)

def parse(X, regex, fields):
	T = X.str.extract(regex).rename(columns = dict(enumerate(fields)));
	return T

def print_conf(D, path):
	## Write to temp location and "sudo mv" to path
	tmpfile = tempfile.mktemp()
	with open(tmpfile, "w") as f:
		for r in D.iteritems():
			f.write("{k}={v}\n".format(
			  k = re.sub(r"^(NodeName|PartitionName)\d+$", r"\1", r[0]),
			  v = r[1]
			))
	subprocess.check_call(["sudo", "cp", tmpfile, path])
	os.remove(tmpfile)

if __name__ == "__main__":
	CLUST_PROV_ROOT = os.environ["CLUST_PROV_ROOT"] if "CLUST_PROV_ROOT" in os.environ \
	                  else "/usr/local/share/slurm_gcp_docker"
	#TODO: check if this is indeed a valid path

	ctrl_hostname = socket.gethostname()

	#
	# mount NFS server
	# Now controller serves as the NFS, so we don't need to mount NFS

	#
	# copy common files to NFS

	# ensure directories exist
	for d in [
	  "/mnt/nfs/clust_conf/slurm",
	  "/mnt/nfs/clust_conf/canine",
	  "/mnt/nfs/workspace"
	]:
		subprocess.check_call("""
		  [ ! -d """ + d + " ] && mkdir -p " + d + """ ||
			true
		  """, shell = True, executable = '/bin/bash')

	subprocess.check_call("sudo chown {U}:{U} /mnt/nfs /mnt/nfs/workspace; sudo chown -R {U}:{U} /mnt/nfs/clust*".format(U = pwd.getpwuid(os.getuid()).pw_name),
	  shell = True, executable = '/bin/bash')

	# delete any preexisting configuration files
	subprocess.check_call("find /mnt/nfs/clust_conf -type f -exec rm -f {} +", shell = True)

	# Slurm conf. file cgroup.conf can be copied-as is
	# (other conf. files will need editing below)
	subprocess.check_call(
	  "sudo cp {CPR}/conf/cgroup.conf /usr/local/etc/cgroup.conf".format(
	    CPR = shlex.quote(CLUST_PROV_ROOT)
	  ),
	  shell = True
	)

	# TODO: copy the tool to run

	#
	# setup Slurm config files

	#
	# slurm.conf
	C = parse_slurm_conf("{CPR}/conf/slurm.conf".format(CPR = shlex.quote(CLUST_PROV_ROOT)))
	C[["ControlMachine", "ControlAddr", "AccountingStorageHost"]] = ctrl_hostname

	# node definitions
	C["NodeName8"] = "{HN}-worker[1-100] CPUs=8 RealMemory=28000 State=CLOUD Weight=3".format(HN = ctrl_hostname)
	C["NodeName1"] = "{HN}-worker[101-2000] CPUs=1 RealMemory=3000 State=CLOUD Weight=2".format(HN = ctrl_hostname)
	C["NodeName4"] = "{HN}-worker[2001-3000] CPUs=4 RealMemory=23000 State=CLOUD Weight=4".format(HN = ctrl_hostname)
	C["NodeName88"] = "{HN}-worker[3001-3500] CPUs=8 RealMemory=50000 State=CLOUD Weight=4".format(HN = ctrl_hostname)
	C["NodeName89"] = "{HN}-worker[3501-3600] CPUs=8 RealMemory=50000 State=CLOUD Weight=4".format(HN = ctrl_hostname) # non-preemptible

	# partition definitions
	C["PartitionName"] = "DEFAULT MaxTime=INFINITE State=UP".format(HN = ctrl_hostname)
	C["PartitionName8"] = "n1-standard-8 Nodes={HN}-worker[1-100]".format(HN = ctrl_hostname)
	C["PartitionName1"] = "n1-standard-1 Nodes={HN}-worker[101-2000]".format(HN = ctrl_hostname)
	C["PartitionName4"] = "n1-highmem-4 Nodes={HN}-worker[2001-3000]".format(HN = ctrl_hostname)
	C["PartitionName88"] = "n1-highmem-8 Nodes={HN}-worker[3001-3500]".format(HN = ctrl_hostname)
	C["PartitionName89"] = "n1-highmem-8-nonp Nodes={HN}-worker[3501-3600]".format(HN = ctrl_hostname)
	C["PartitionName888"] = "main Nodes={HN}-worker[1-3500] Default=YES".format(HN = ctrl_hostname) # Default partition, preemptible
	C["PartitionName889"] = "nonpreemptible Nodes={HN}-worker[3501-3600] Default=NO".format(HN = ctrl_hostname) # Non-preemptible partition
	C["PartitionName999"] = "all Nodes={HN}-worker[1-3600] Default=NO".format(HN = ctrl_hostname)

	print_conf(C, "/usr/local/etc/slurm.conf")

	nonstandardparts = ["all", "main", "nonpreemptible"]
	nonpreemptible_range = range(3501, 3600 + 1)

	#
	# save node lookup table
	parts = C.filter(regex = r"^Partition").apply(lambda x : x.split(" "))
	parts = pd.DataFrame(
	  [{ "partition" : x[0], **{y[0] : y[1] for y in [z.split("=") for z in x[1:]]}} for x in parts]
	)
	parts = parsein(parts, "Nodes", r"(.*)\[(\d+)-(\d+)\]", ["prefix", "start", "end"])
	parts = parts.loc[~parts["start"].isna() & (~parts["partition"].isin(nonstandardparts))].astype({ "start" : int, "end" : int })

	nodes = []
	for part in parts.itertuples():
		nodes.append(pd.DataFrame([[part.partition, False if x in nonpreemptible_range else True, part.prefix + str(x)] for x in range(part.start, part.end + 1)], columns = ["machine_type", "preemptible", "idx"]))
	nodes = pd.concat(nodes).set_index("idx")

	nodes.to_pickle("/mnt/nfs/clust_conf/slurm/host_LuT.pickle")

	#
	# save backend config inside container
	canine_backend_conf = parse_canine_conf_from_env()
	tmpfile = tempfile.mktemp()
	with open(tmpfile, "w") as f:
		json.dump(canine_backend_conf, f, indent=2)
	subprocess.check_call(["sudo", "cp", tmpfile, "/usr/local/etc/canine_backend_conf.json"])
	os.remove(tmpfile)

	#
	# slurmdbd.conf
	C = parse_slurm_conf("{CPR}/conf/slurmdbd.conf".format(CPR = shlex.quote(CLUST_PROV_ROOT)))
	C["DbdHost"] = ctrl_hostname

	print_conf(C, "/usr/local/etc/slurmdbd.conf")
	subprocess.check_call(["sudo", "chown", "slurm:slurm", "/usr/local/etc/slurmdbd.conf"])
	subprocess.check_call(["sudo", "chmod", "600", "/usr/local/etc/slurmdbd.conf"])

	#
	# start Slurm controller
	print("Checking for running Slurm controller ... ")

	subprocess.check_call("""
	  echo -n "Waiting for Slurm conf ..."
	  while [ ! -f {conf_path} ]; do
	    sleep 1
	    echo -n "."
	  done
	  echo
	  pgrep slurmdbd || sudo -E slurmdbd;
	  echo -n "Waiting for database to be ready ..."
	  while ! sacctmgr -i list cluster &> /dev/null; do
	    sleep 1
	    echo -n "."
	  done
	  echo
	  sudo -E sacctmgr -i add cluster cluster
	  pgrep slurmctld || sudo -E slurmctld -c &&
	    sudo -E slurmctld reconfigure;
	  pgrep munged || sudo -E munged -f
	  """.format(conf_path = "/usr/local/etc/slurm.conf"),
	  shell = True,
	  stderr = subprocess.DEVNULL,
	  executable = '/bin/bash'
	)

	#
	# indicate that container is ready
	subprocess.check_call("sudo touch /.started", shell = True)
