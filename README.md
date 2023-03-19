# Docker Platform

## Introduction

Platform for easy management of Docker Containers on
single remote hosts

## Docker Package
The core idea behind this platform is a so-called "Docker Package" folder that consists of several files, including a metadata file named ```docker.pkg```. This package is synched to the remote host using rSync and can be executed according the given ```docker-compose.yml```. Additionally a pre- and a post-script can be executed before and after starting the Docker services.

The metadata file contains:
- ```NAME```: The name of the package (used as ID for sync)
- ```DESCRIPTION```: Description of the package
- ```ADDITIONAL_FILES```: Comma-separated list of files and folders that should be synched to the remote server
- ```PRE_HOOK```: Script file that is executed before starting the services
- ```POST_HOOK```: Script file that is executed after services have been startet

## Setup
### General Setup
The remote host needs a user that belongs to the ```docker```-group. For convenience, RSA keys of the local machine should be uploaded using ```ssh-copy-id user@host``` and SSHd should allow ```PubkeyAuthentication```, otherwise the scipts are forced to enter a password on each connection.
### Linux Packages
The platform scripts require following pre-installed packages:
- docker-ce (> 5:23.0.1)
- docker-ce-cli (> 5:23.0.1)
- docker-compose (>2.16)
- containerd.io (>1.6)
- zip
- rsynch

### Environment
The following environment variables must be set and exported (e.g. in ~/.profile of each eligible user)
```
export DOCKER_PLATFORM_HOME="/docker"
export DOCKER_PLATFORM_BACKUPS="/backups"
```

This toolchain has been successfully tested on Debian GNU/Linux 11 (bullseye), other Linux distributions may be supported in the future too.

## Binaries
Folder ```bin``` contains a variety of toolchain scripts, of which some of them are synched to the remote host.

### Local Binaries
- **deploy.sh** - Master script for deploying packages, scripts and config files
- **build.sh** - Creates and pushes Docker images according to the specified build folder

### Remote Binaries
The following scripts are synched to the remote host:
- **armageddon.sh** - Script for tearing down the whole Docker environment
- **backup.sh** - Backs up all container packages, volumes and environment variables
- **common.sh** - Just a sourcable script holding common functions
- **hosts.sh** - Updates and writes docker hostnames to the remote server's host config
- **networks.sh** - Creates external networks according to the network configuration in ```/etc/networks.conf```
- **restore.sh** - Restores packages, volumes and environment variables by a given backup file
- **run.sh** - Runs a given Docker package and executes pre- and post-scripts
- **stop.sh** - Stops a given Docker package

<br>
<br>

- - -
Made with ❤️ in Bavaria
<br>
© 2018-2023, <a href="https://www.alexanderwolz.de"> Alexander Wolz