#!/usr/bin/env python3

import os
import subprocess
services_dir = os.path.join(os.path.dirname(__file__), "services")

prefectserver = os.path.join(services_dir, "prefectserver.service")
caninebackend = os.path.join(services_dir, "caninebackend.service")
jupyternotebook = os.path.join(services_dir, "jupyternotebook.service")
wolfgui = os.path.join(services_dir, "wolfgui.service")

def main():
    subprocess.check_call(["sudo", "cp", prefectserver, "/etc/systemd/system/prefectserver.service"])
    subprocess.check_call(["mkdir", "-p", os.path.expanduser("~/.config/systemd/user")])
    subprocess.check_call(["cp", caninebackend, os.path.expanduser("~/.config/systemd/user/caninebackend.service")])
    subprocess.check_call(["cp", jupyternotebook, os.path.expanduser("~/.config/systemd/user/jupyternotebook.service")])
    subprocess.check_call(["cp", wolfgui, os.path.expanduser("~/.config/systemd/user/wolfgui.service")])

    # Prefect 3 clients use PREFECT_API_URL instead of ~/.prefect/backend.toml
    profile = os.path.expanduser("~/.profile")
    export_line = "export PREFECT_API_URL=http://127.0.0.1:4200/api\n"
    with open(profile, "a+") as f:
        f.seek(0)
        if export_line not in f.read():
            f.write(export_line)

    subprocess.check_call(["sudo", "systemctl", "daemon-reload"])
    subprocess.check_call(["systemctl", "--user", "daemon-reload"])

if __name__ == "__main__":
    main()
