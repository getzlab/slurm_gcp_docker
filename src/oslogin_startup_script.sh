#! /bin/bash
# Install shells to prevent os-login errors

if ! [ -f /.startup ]; then
    apt update
    apt -y install tcsh zsh
fi
