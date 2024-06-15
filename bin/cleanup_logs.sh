#!/bin/bash
# Copyright (C) 2023 Alexander Wolz <mail@alexanderwolz.de>

if ! [ $(id -u) = 0 ]; then
    echo "Must run as root user"
    exit 1
fi

#delete old log rotations
sudo rm -rf /var/lib/docker/containers/*/*-json.log.*

#truncate current log files
sudo sh -c 'truncate -s 0 /var/lib/docker/containers/*/*-json.log'

echo "Done cleaning all docker logs"