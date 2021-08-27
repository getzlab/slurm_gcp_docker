#!/usr/bin/env python3

import os
import subprocess
services_dir = os.path.join(os.path.dirname(__file__), "services")

prefectserver = os.path.join(services_dir, "prefectserver.service")
caninebackend = os.path.join(services_dir, "caninebackend.service")
jupyternotebook = os.path.join(services_dir, "jupyternotebook.service")

def main():
    subprocess.check_call(["sudo", "cp", prefectserver, "/etc/systemd/system/prefectserver.service"])
    subprocess.check_call(["mkdir", "-p", os.path.expanduser("~/.config/systemd/user")])
    subprocess.check_call(["cp", caninebackend, os.path.expanduser("~/.config/systemd/user/caninebackend.service")])
    subprocess.check_call(["cp", jupyternotebook, os.path.expanduser("~/.config/systemd/user/jupyternotebook.service")])

    subprocess.check_call(["mkdir", "-p", os.path.expanduser("~/.prefect")])
    with open(os.path.expanduser("~/.prefect/backend.toml"), "w") as f:
        f.write('backend = "server"\n')

    subprocess.check_call(["sudo", "systemctl", "daemon-reload"])
    subprocess.check_call(["systemctl", "--user", "daemon-reload"])

if __name__ == "__main__":
    main()
