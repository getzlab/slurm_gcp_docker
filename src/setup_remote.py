#!/usr/bin/env python3
import subprocess, os, sys, re, time, textwrap, getpass

this_dir = os.path.dirname(__file__)
SLURM_GCP_DOCKER_DIR = os.path.realpath(os.path.join(this_dir, ".."))

def download_getzlab_ssh_key():
    pubkey = os.path.join(SLURM_GCP_DOCKER_DIR, "getzlabkey.pub")
    seckey = os.path.join(SLURM_GCP_DOCKER_DIR, "getzlabkey")
    if not os.path.exists(pubkey):
        subprocess.check_call(["gsutil", "cp", "gs://getzlab-secrets/github-service-account/github.pub", pubkey])
    if not os.path.exists(seckey):
        subprocess.check_call(["gsutil", "cp", "gs://getzlab-secrets/github-service-account/github", seckey])

def get_current_project():
    ## Assuming on a GCE instance
    project = subprocess.check_output(
        "curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/project/project-id",
        shell=True
    )
    project = project.decode()
    return project

def get_current_instance_name():
    name = subprocess.check_output(
        "curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/name",
        shell=True
    )
    name = name.decode()
    return name

def get_current_zone():
    ## Assuming on a GCE instance
    zone = subprocess.check_output(
        "curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/zone",
        shell=True
    )
    zone = zone.decode()
    zone = re.sub(".*/", "", zone)
    return zone

def create_wolfcontroller(instance_name, project=None, zone=None, machine_type="n1-standard-4", boot_disk_size=200):
    if project is None:
        project = get_current_project()
    if zone is None:
        zone = get_current_zone()
    
    wolfuser = getpass.getuser()
    ## I used "enable-oslogin=TRUE", which ensures consistent UID within a project.
    subprocess.check_call(
        f"gcloud compute instances create {instance_name} \
            --quiet \
            --project {project} \
            --zone {zone} \
            --machine-type {machine_type} \
            --image ubuntu-minimal-2004-focal-v20210511 \
            --image-project ubuntu-os-cloud \
            --boot-disk-size {boot_disk_size}GB \
            --boot-disk-type pd-standard \
            --scopes cloud-platform,compute-rw \
            --tags=wolfcontroller \
            --metadata=enable-oslogin=TRUE,wolfuser={wolfuser}"
            #--metadata-from-file startup-script={startup_script},shutdown-script={shutdown_script} \
            , shell=True
    )

    ## Waiting for ssh working
    n = 0
    while True:
        time.sleep(6)
        try:
            subprocess.check_call(f"gcloud compute ssh --project {project} --quiet {instance_name} --zone {zone} --command 'true'", shell=True, stderr=subprocess.DEVNULL)
            break
        except Exception as err:
            if n >= 5:
                raise err
            pass
        finally:
            n += 1

    ## Copy stuff and run user script
    subprocess.check_call(
        f"gcloud compute scp {SLURM_GCP_DOCKER_DIR}/ {instance_name}:slurm_gcp_docker --zone {zone} --recurse --project {project} --quiet --scp-flag='-q'", shell=True
    )
    subprocess.check_call(
        f"gcloud compute scp ~/.config/gcloud/ {instance_name}:copied_gcloud_dir --zone {zone} --recurse --project {project} --quiet --scp-flag='-q'", shell=True
    )

    ## Execute setup script
    subprocess.check_call(
        f'gcloud compute ssh {instance_name} --zone {zone} --project {project} -- -o "StrictHostKeyChecking no" -o "UserKnownHostsFile /dev/null" -T "bash ~/slurm_gcp_docker/src/setup_remote_user_startup_script.sh"', shell=True
    )

    print(textwrap.dedent(f"""
    Connect to the controller with following command and open browser at http://localhost:8080
        gcloud compute ssh --project {project} --zone {zone} {instance_name} -- -L 8080:localhost:8080 -L 8889:localhost:8889 -L 8888:localhost:8888 -L 4200:localhost:4200
    """))

def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=str)
    parser.add_argument("--zone", type=str)
    parser.add_argument("instance_name", type=str)
    parser.add_argument("--machine-type", type=str, default="n1-standard-4")
    parser.add_argument("--boot-disk-size", type=int, default=200)
    args = parser.parse_args()
    download_getzlab_ssh_key()
    create_wolfcontroller(args.instance_name, project=args.project, zone=args.zone, machine_type=args.machine_type, boot_disk_size=args.boot_disk_size)

if __name__ == "__main__":
    main()