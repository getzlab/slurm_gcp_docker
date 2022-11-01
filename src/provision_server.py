#!/usr/bin/python3

import argparse
import io
import os
import pwd
import pandas as pd
import numpy as np
import re
import shlex
import socket
import subprocess
import itertools
# sys.path.append("/home/jhess/j/proj/") # TODO: remove this line when Capy is a package
# from capy import txt

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

def print_conf(D, path, owner = None, perm = None):
	if os.path.exists(path):
		subprocess.check_call(["sudo", "rm", "-rf", path])
	with open(path, "w") as f:
		for r in D.iteritems():
			f.write("{k}={v}\n".format(
			  k = re.sub(r"^(NodeName|PartitionName)\d+$", r"\1", r[0]),
			  v = r[1]
			))
	if perm is not None:
		os.chmod(path, mode=perm)
	if owner is not None:
		subprocess.check_call(["sudo", "chown", str(pwd.getpwnam(owner)[2]), path])

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
	  "/mnt/nfs/clust_scripts",
	  "/mnt/nfs/clust_logs",
	  "/mnt/nfs/workspace"
	]:
		subprocess.check_call("""
		  [ ! -d """ + d + " ] && mkdir -p " + d + """ ||
			true
		  """, shell = True, executable = '/bin/bash')

	subprocess.check_call("sudo chown {U}:{U} /mnt/nfs /mnt/nfs/workspace; sudo chown -R {U}:{U} /mnt/nfs/clust*".format(U = pwd.getpwuid(os.getuid()).pw_name),
	  shell = True, executable = '/bin/bash')

	# delete any preexisting configuration files
	subprocess.check_call("find /mnt/nfs/clust_conf -type f ! -name nodetypes.json -exec rm -f {} +", shell = True)

	# delete any preexisting worker log files
	subprocess.check_call("find /mnt/nfs/clust_logs -type f -exec rm -f {} +", shell = True)

	# Slurm conf. file cgroup.conf and boto conf can be copied-as is
	# (other conf. files will need editing below)
	subprocess.check_call(
	  "cp {CPR}/conf/cgroup.conf /mnt/nfs/clust_conf/slurm".format(
	    CPR = shlex.quote(CLUST_PROV_ROOT)
	  ),
	  shell = True
	)

	# scripts
	subprocess.check_call(
	  "cp -r {CPR}/src/* /mnt/nfs/clust_scripts".format(CPR = shlex.quote(CLUST_PROV_ROOT)),
	  shell = True
	)

	# TODO: copy the tool to run

	#
	# setup Slurm config files

	#
	# slurm.conf
	C = parse_slurm_conf("{CPR}/conf/slurm.conf".format(CPR = shlex.quote(CLUST_PROV_ROOT)))
	C[["ControlMachine", "ControlAddr", "AccountingStorageHost"]] = ctrl_hostname

	## Additional nodes can be added to conf/nodetypes.json
	## E.g.
	##   { "type": "n1-highmem-16", "cpus": "16", "realmemory": "102200", "weight": "4" , "number":   10, "preemptible":  True }
	##   { "type": "n1-highmem-32", "cpus": "32", "realmemory": "204200", "weight": "4" , "number":   10, "preemptible":  True }
	NODE_TYPES = pd.read_json("/mnt/nfs/clust_conf/slurm/nodetypes.json" if os.path.exists("/mnt/nfs/clust_conf/slurm/nodetypes.json") else "{CPR}/conf/nodetypes.json".format(CPR = shlex.quote(CLUST_PROV_ROOT)))
	NODE_TYPES.to_json("/mnt/nfs/clust_conf/slurm/nodetypes.json", orient = "records", indent = 1)
	NODE_TYPES["range_end"]   = np.cumsum(NODE_TYPES["number"])
	NODE_TYPES["range_start"] = np.append([1], NODE_TYPES["range_end"][:-1] + 1) 
	NODE_TYPES["nodes"]       = NODE_TYPES.apply(lambda row: "{HN}-worker[{range_start}-{range_end}]".format(HN=ctrl_hostname, **row), axis=1)
	NODE_TYPES["partition1"]  = np.where(NODE_TYPES["preemptible"], NODE_TYPES["type"], NODE_TYPES["type"] + "-nonp")
	NODE_TYPES["partition2"]  = np.where(NODE_TYPES["preemptible"], "main", "nonpreemptible")

	# node definitions
	for idx, row in NODE_TYPES.iterrows():
		C["NodeName" + str(idx+1)] = "{nodes} CPUs={cpus} RealMemory={realmemory} State=CLOUD Weight={weight}".format(HN=ctrl_hostname, **dict(row))

	# partition definitions
	C["PartitionName"] = "DEFAULT MaxTime=INFINITE State=UP".format(HN = ctrl_hostname)

	for idx, row in NODE_TYPES.iterrows():
		C["PartitionName" + str(idx+1)] = "{partition1} Nodes={nodes}".format(HN=ctrl_hostname, **dict(row))

	C["PartitionName888"] = "main Nodes={} Default=YES".format(",".join(NODE_TYPES.loc[NODE_TYPES["partition2"] == "main"]["nodes"]))
	C["PartitionName889"] = "nonpreemptible Nodes={} Default=NO".format(",".join(NODE_TYPES.loc[NODE_TYPES["partition2"] == "nonpreemptible"]["nodes"]))
	C["PartitionName999"] = "all Nodes={} Default=NO".format(",".join(NODE_TYPES["nodes"]))

	print_conf(C, "/mnt/nfs/clust_conf/slurm/slurm.conf")

	nonstandardparts = ["all", "main", "nonpreemptible"]

	#
	# save node lookup table
	parts = C.filter(regex = r"^Partition").apply(lambda x : x.split(" "))
	parts = pd.DataFrame(
	  [{ "partition" : x[0], **{y[0] : y[1] for y in [z.split("=") for z in x[1:]]}} for x in parts]
	)
	parts = parsein(parts, "Nodes", r"(.*)\[(\d+)-(\d+)\]", ["prefix", "start", "end"])
	parts = parts.loc[~parts["start"].isna() & (~parts["partition"].isin(nonstandardparts))].astype({ "start" : int, "end" : int })

	nonpreemptible_range = list(itertools.chain(*[range(x, y + 1) for x, y in parts.loc[parts["partition"].str.contains(r"-nonp$"), ["start", "end"]].values]))

	nodes = []
	for part in parts.itertuples():
		nodes.append(pd.DataFrame([[part.partition, False if x in nonpreemptible_range else True, part.prefix + str(x)] for x in range(part.start, part.end + 1)], columns = ["machine_type", "preemptible", "idx"]))
	nodes = pd.concat(nodes).set_index("idx")

	nodes.to_pickle("/mnt/nfs/clust_conf/slurm/host_LuT.pickle")

	#
	# slurmdbd.conf
	C = parse_slurm_conf("{CPR}/conf/slurmdbd.conf".format(CPR = shlex.quote(CLUST_PROV_ROOT)))
	C["DbdHost"] = ctrl_hostname

	print_conf(C, "/mnt/nfs/clust_conf/slurm/slurmdbd.conf", perm=0o600, owner="slurm")

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
	  export SLURM_CONF={conf_path};
	  pgrep slurmdbd || sudo -E slurmdbd;
	  echo -n "Waiting for database to be ready ..."
	  while ! sacctmgr -i list cluster &> /dev/null; do
	    sleep 1
	    echo -n "."
	  done
	  echo
	  sudo -E sacctmgr -i add cluster cluster
	  pgrep slurmctld || sudo -E slurmctld -c -f {conf_path} &&
	    sudo -E slurmctld reconfigure;
	  pgrep munged || sudo -E munged -f
	  """.format(conf_path = "/mnt/nfs/clust_conf/slurm/slurm.conf"),
	  shell = True,
	  stderr = subprocess.DEVNULL,
	  executable = '/bin/bash'
	)

	#
	# indicate that container is ready
	subprocess.check_call("sudo touch /.started", shell = True)
