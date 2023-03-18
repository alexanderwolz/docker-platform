# Docker Platform

## Introduction

Platform for easy management of Docker Containers on
single remote hosts

## Environment
The following environment variables must be set and exported (e.g. in ~/.profile)
```
export DOCKER_PLATFORM_HOME="/docker"
export DOCKER_PLATFORM_BACKUPS="/backups"
```

This toolchain has been successfully tested on Debian GNU/Linux 11 (bullseye)

## Local Binaries

- **build.sh.** Creates and pushes Docker images according to the specified build folder
- **deploy.sh.** Master script for deploying packages, scripts and config files

## Remote Binaries

The following scripts are synched to the remote host:

- **armageddon.sh.** Script for tearing down the whole Docker environment
- **backup.sh.** Backs up all container packages, volumes and environment variables
- **common.sh.** Just a sourcable script holding common functions
- **hosts.sh.** Updates and writes docker hostnames to the remote server's host config
- **networks.sh.** Creates external networks according to the network configuration in /etc/networks.conf
- **restore.sh.** Restores packages, volumes and environment variables by a given backup file
- **run.sh.** Runs a given Docker package
- **run.sh.** Stops a given Docker package

<br>
Made with ❤️ in Bavaria
<br>
© 2018-2023, <a href="https://www.alexanderwolz.de"> Alexander Wolz