# slurm_gcp_docker

Builds and publishes a Docker image that runs an autoscaling SLURM cluster on GCP. The image is the primary artifact — the Python package (`slurm_gcp_docker`) is a thin installer/helper that is conditionally installed by canine on non-Docker hosts.

GitHub: https://github.com/getzlab/slurm_gcp_docker  
Published image: `gcr.io/broad-getzlab-workflows/slurm_gcp_docker`

## What This Repo Actually Is

This is primarily an infrastructure/Docker repo. The Python package it installs is minimal scaffolding. The real output is the Docker image defined in `slurm_gcp_docker/Dockerfile`, which canine's `GCPTransient` backend launches on GCP VMs.

## Image Contents (slurm_gcp_docker/Dockerfile)

Base: `ubuntu:22.04`

Key components installed in the image:
- **Python 3.14** (from the deadsnakes PPA; `/usr/bin/python3` points at it)
- **Slurm 24.05.4** (built from source)
- MariaDB, Munge, NFS server
- Google Cloud CLI 588.0.0, from Google's tarball. It runs on its own bundled Python
  (`platform/bundledpythonunix`, which already has `crcmod` and `google_crc32c`), not the
  image's 3.14; keep it that way, so a gcloud release and the image's Python can move
  independently.
- AWS CLI
- Podman 4.3.1 + Nvidia container toolkit
- Python packages in-image: `pandas>=2.2`, `crcmod`, `google-crc32c`, `requests`

Entrypoint: `slurm_gcp_docker/docker_entrypoint_controller.sh`

## slurm_gcp_docker/ Structure

```
slurm_gcp_docker/
├── Dockerfile                         # main image definition
├── VERSION                            # current: 0.18.5
├── build_master_images.py             # builds and pushes the Docker image to GCR
├── provision_server.py                # provisions the SLURM controller VM
├── setup_remote.py                    # sets up remote user environment
├── slurm_resume.py                    # SLURM ResumeProgram: starts GCP nodes
├── slurm_suspend.sh                   # SLURM SuspendProgram: terminates GCP nodes
├── install_service.py                 # installs systemd services; exports PREFECT_API_URL
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
python slurm_gcp_docker/build_master_images.py
# This runs docker build and pushes to GCR.
```

`setup.py` is unusual: running `pip install .` on the controller host triggers `test_controller_environment.check_all()` (validates gcloud, Docker, etc.) and `docker pull gcr.io/broad-getzlab-workflows/slurm_gcp_docker:latest`.

## Tests

`test/test_worker.sh` — shell script that creates real GCP VMs via `gcloud compute instances create` to validate the worker boot process. No Python unit tests exist.

## Python Version Upgrade Notes (3.8 → 3.14) ✅ DONE

The Dockerfile installs `python3.14` from `deadsnakes/ppa` and points `/usr/bin/python3` at
it; in-image `pandas` is `>=2.2`, matching canine.

## Prefect 3 Service Notes

`services/prefectserver.service` — The `ExecStart` command (`prefect server start --use-volume --volume-path /var/lib/prefectserver`) is already Prefect 3 syntax. No change needed to the service file itself.

**`install_service.py`** ✅ no longer writes `~/.prefect/backend.toml` (Prefect 3 has no such file); it exports `PREFECT_API_URL=http://127.0.0.1:4200/api` instead. wolF controllers don't use these services anyway: wolF starts its own Prefect server (see wolF's `CLAUDE.md`).

## Post-Upgrade Versioning

After changes are complete:
1. Update `slurm_gcp_docker/VERSION` (e.g., `0.18.6`).
2. Build and push new image: `python slurm_gcp_docker/build_master_images.py`.
3. Create the matching git tag (e.g. `v0.18.6`).
4. Update `canine/setup.py` to pin to the new tag.
