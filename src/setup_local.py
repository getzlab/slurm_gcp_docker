#!/usr/bin/env python3

import subprocess, os, sys, re, shutil, textwrap, getpass

def error(msg, dedent=True):
    if dedent:
        msg = textwrap.dedent(msg)
    print(msg)
    #print("\nPlease refer to https://github.com/getzlab/wolF/wiki/Setup for complete setup instructions")
    sys.exit(1)

def check_gcloud_auth():
    if not shutil.which("gcloud"):
        error("gcloud is not installed")
    auth_email = subprocess.check_output('gcloud config list account --format "value(core.account)"', shell=True)
    auth_email = auth_email.decode().rstrip().split("\n")[0]
    if auth_email.endswith("gserviceaccount.com"):
        error("""\
        gcloud is using service account, please first run
            gcloud auth login --update-adc  """)
        sys.exit(1)
    ## Seems there is no easy way to check if 'gcloud auth application-default login' has been run??

def check_git():
    if not shutil.which("git"):
        error("""\
        git is not installed  """)
    return

# sudo apt-get update && sudo apt-get install git python3-pip nfs-kernel-server docker.io nfs-common
def check_nfs():
    if not shutil.which("exportfs"):
        error("""\
        NFS is not installed, please run:
            sudo apt-get update && sudo apt-get install nfs-kernel-server nfs-common """)

def check_docker():
    if not shutil.which("docker"):
        error("""\
        docker is not installed, please first run:
            sudo apt-get update && sudo apt-get install docker.io  """)
    try:
        subprocess.check_call("docker info", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        ## TODO: I think we should avoid this issue by always using "sudo docker"
        error("""\
        Error running docker command, you may try the following command and re-login:
            sudo groupadd docker; sudo usermod -aG docker $USER
        """)

if __name__ == "__main__":
    check_docker()
    check_gcloud_auth()
    check_git()
    check_nfs()

    VERSION = open("VERSION").read().rstrip()
    IVERSION = re.sub(r"\.","-", VERSION)
    gitrev = subprocess.check_output("git rev-parse --short HEAD", shell=True).rstrip().decode()

    subprocess.check_call("./docker_build.sh {}".format(" ".join(sys.argv[1:])), shell=True)
    subprocess.check_call("./generate_container_host_image.py -i slurm-gcp-docker-{}-{}-{}".format(IVERSION, gitrev, getpass.getuser()), shell=True)
