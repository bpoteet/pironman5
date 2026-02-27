#!/bin/bash

set -euo pipefail
trap 'echo "Error occurred. Exiting..." >&2; exit 1' ERR

# Check root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Check if argument exists before accessing \$1
if [ $# -ge 1 ] && [ "$1" == "--uninstall" ]; then
    exit 0
fi

# Detect package manager
if command -v apt-get > /dev/null 2>&1; then
    PKG_MANAGER="apt"
elif command -v pacman > /dev/null 2>&1; then
    PKG_MANAGER="pacman"
else
    echo "Error: No supported package manager found (apt-get or pacman)"
    exit 1
fi

if [ "$PKG_MANAGER" = "apt" ]; then
    # Debian/Ubuntu: influxdb is not in the standard apt repos, so we must add
    # the InfluxData APT source and GPG key before it can be installed.
    echo "Setup influxdb install source..."
    # influxdata-archive.key GPG fingerprint:
    #   Primary key fingerprint: 24C9 75CB A61A 024E E1B6  3178 7C3D 5715 9FC2 F927
    #   Subkey fingerprint:      9D53 9D90 D332 8DC7 D6C8  D3B9 D8FF 8E1F 7DF8 B07E
    curl --silent --location -O https://repos.influxdata.com/influxdata-archive.key
    gpg --show-keys --with-fingerprint --with-colons ./influxdata-archive.key 2>&1 | grep -q '^fpr:\+24C975CBA61A024EE1B631787C3D57159FC2F927:$' && cat influxdata-archive.key | gpg --dearmor | sudo tee /etc/apt/keyrings/influxdata-archive.gpg > /dev/null
    echo 'deb [signed-by=/etc/apt/keyrings/influxdata-archive.gpg] https://repos.influxdata.com/debian stable main' | sudo tee /etc/apt/sources.list.d/influxdata.list
    rm influxdata-archive.key
    apt-get update
else
    # Arch/Manjaro: influxdb is available directly in the community repo, so no
    # extra source or GPG key setup is needed. The package will be installed by
    # the main installer via 'pacman -S influxdb'.
    echo "Skipping InfluxDB APT repo setup (not needed on Arch/Manjaro — influxdb is available via pacman directly)."
fi
