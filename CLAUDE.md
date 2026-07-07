# slurm_gcp_docker

Builds and publishes a Docker image that runs an autoscaling SLURM cluster on GCP. The image is the primary artifact — the Python package (`slurm_gcp_docker`) is a thin installer/helper that is conditionally installed by canine on non-Docker hosts.

GitHub: https://github.com/getzlab/slurm_gcp_docker  
Published image: `gcr.io/broad-getzlab-workflows/slurm_gcp_docker`

## What This Repo Actually Is

This is primarily an infrastructure/Docker repo. The Python package it installs is minimal scaffolding. The real output is the Docker image defined in `src/Dockerfile`, which canine's `GCPTransient` backend launches on GCP VMs.

## Image Contents (src/Dockerfile)

Base: `ubuntu:22.04`

Key components installed in the image:
- **Python 3.8** (from deadsnakes PPA — must be upgraded to 3.14)
- **Slurm 24.05.4** (built from source)
- MariaDB, Munge, NFS server
- Google Cloud SDK 457.0.0
- AWS CLI
- Podman 4.3.1 + Nvidia container toolkit
- Python packages in-image: `pandas==1.4.2` (upgrade to 2.x), `crcmod`, `google-crc32c`, `requests`

Entrypoint: `src/docker_entrypoint_controller.sh`

## src/ Structure

```
src/
├── Dockerfile                         # main image definition
├── VERSION                            # current: v0.17.0
├── build_master_images.py             # builds and pushes the Docker image to GCR
├── provision_server.py                # provisions the SLURM controller VM
├── setup_remote.py                    # sets up remote user environment
├── slurm_resume.py                    # SLURM ResumeProgram: starts GCP nodes
├── slurm_suspend.sh                   # SLURM SuspendProgram: terminates GCP nodes
├── install_service.py                 # installs systemd services; writes ~/.prefect/backend.toml (remove this)
├── hung_disk_daemon.py                # watchdog for stuck attached disks
├── test_controller_environment.py     # pre-flight checks run at `pip install` time
├── docker_entrypoint_controller.sh    # container entrypoint
├── docker_entrypoint_worker.sh        # worker container entrypoint
├── services/
│   ├── caninebackend.service          # systemd: canine backend server
│   ├── prefectserver.service          # systemd: Prefect server (syntax already Prefect 3-compatible)
│   ├── wolfgui.service                # systemd: wolF web GUI
│   └── jupyternotebook.service        # systemd: Jupyter
└── podman_conf/                       # Podman config for running jobs in containers
```

## Building the Image

```bash
# From inside the repo:
python src/build_master_images.py
# This runs docker build and pushes to GCR.
```

`setup.py` is unusual: running `pip install .` on the controller host triggers `test_controller_environment.check_all()` (validates gcloud, Docker, etc.) and `docker pull gcr.io/broad-getzlab-workflows/slurm_gcp_docker:latest`.

## Tests

`test/test_worker.sh` — shell script that creates real GCP VMs via `gcloud compute instances create` to validate the worker boot process. No Python unit tests exist.

## Python Version Upgrade Notes (3.8 → 3.14)

**Python in the Dockerfile is hardcoded to 3.8.** The relevant lines in `src/Dockerfile` use `deadsnakes/ppa` to install `python3.8`. To upgrade:

1. Change the PPA install from `python3.8` to `python3.14` in the `RUN apt-get install` lines.
2. Update all `python3.8` binary references and `update-alternatives` calls to `python3.14`.
3. Update in-image `pandas==1.4.2` → `>=2.2` to match canine.
4. Verify all other in-image Python packages install cleanly on 3.14.

## Prefect 3 Service Notes

`services/prefectserver.service` — The `ExecStart` command (`prefect server start --use-volume --volume-path /var/lib/prefectserver`) is already Prefect 3 syntax. No change needed to the service file itself.

**`install_service.py` must be updated:** It currently writes `~/.prefect/backend.toml` with `backend = "server"`. This file does not exist in Prefect 3. Remove that write, and instead export `PREFECT_API_URL=http://127.0.0.1:4200/api` in the appropriate shell profile or systemd `Environment=` directive so that wolF and canine processes on the controller node connect to the Prefect server automatically.

## Post-Upgrade Versioning

After changes are complete:
1. Update `src/VERSION` (e.g., `v0.18.0`).
2. Build and push new image: `python src/build_master_images.py`.
3. Create git tag `v0.18.0`.
4. Update `canine/setup.py` to pin to the new tag.
