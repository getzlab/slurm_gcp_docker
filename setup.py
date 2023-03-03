from setuptools import setup
from src import test_controller_environment

import os
import subprocess

# ensure prerequisites are satisfied.
test_controller_environment.check_all()

# pull Docker
subprocess.run("docker pull gcr.io/broad-getzlab-workflows/slurm_gcp_docker:latest", shell = True)

# get version
with open(f"{os.path.dirname(__file__)}/src/VERSION") as v:
    version = v.read().rstrip()[1:]

setup(
    name = 'slurm_gcp_docker',
    version = version,
    description = 'An autoscaling Slurm cluster on Google Cloud Platform',
    url = 'https://github.com/getzlab/slurm_gcp_docker',
    author = 'Julian Hess/Jialin Ma/Oliver Priebe - Broad Institute - Cancer Genome Computational Analysis',
    author_email = 'jhess@broadinstitute.org',
    python_requires = ">3.7",
    #long_description = long_description,
    #long_description_content_type = 'text/markdown',
    classifiers = [
        "Development Status :: 4 - Beta",
        "Programming Language :: Python :: 3",
        "Intended Audience :: Science/Research",
        "Topic :: Scientific/Engineering :: Bio-Informatics",
        "Topic :: System :: Clustering",
        "Topic :: System :: Distributed Computing",
        "License :: OSI Approved :: BSD License"
    ],
    license="BSD3",
)
