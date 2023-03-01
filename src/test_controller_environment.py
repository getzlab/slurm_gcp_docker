#!/usr/bin/env python3

import subprocess, os, sys, re, shutil, textwrap, getpass

def error(msg, dedent=True):
    if dedent:
        msg = textwrap.dedent(msg)
    raise RuntimeError(msg)

def check_gcloud_auth():
    # check if we even have gcloud
    if not shutil.which("gcloud"):
        error("gcloud is not installed")

    # make sure that we've authenticated at all
    try:
        subprocess.check_call("gcloud auth print-access-token", shell = True, stderr = subprocess.DEVNULL, stdout = subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        error("""\
        You have not yet authenticated with Google Cloud. Please run
            gcloud auth login --update-adc""", dedent = True)

    # make sure we've authenticated as a user, not a service account
    auth_email = subprocess.check_output('gcloud config list account --format "value(core.account)"', shell=True)
    auth_email = auth_email.decode().rstrip().split("\n")[0]
    if auth_email.endswith("gserviceaccount.com"):
        error("""\
        gcloud is using service account, please first run
            gcloud auth login --update-adc""", dedent = True)

    # make sure we've authenticated with application credentials
    try:
        subprocess.check_call("gcloud auth application-default print-access-token", shell = True, stderr = subprocess.DEVNULL, stdout = subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        error("""\
        You have not fully authenticated with Google Cloud. Please run
            gcloud auth login --update-adc
        Note the '--update-adc' flag!""", dedent = True)

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
        subprocess.check_call("sudo docker info", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        error("""\
        Docker is misconfigured! Please verify that it is properly installed.
        """)
    try:
        subprocess.check_call("docker info", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        error("""\
        You need to add your username to the `docker` group to allow sudoless Docker.
        Please run `sudo groupadd docker; sudo usermod -aG docker $USER` and login again.
        """)

def check_all():
    check_docker()
    check_gcloud_auth()
    check_git()
    check_nfs()
