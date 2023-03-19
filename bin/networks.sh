#!/bin/bash
# Copyright (C) 2023 Alexander Wolz <mail@alexanderwolz.de>


if [ -z $SCRIPT_DIR ]; then
    echo "Setting up docker networks .."
else
    echo "Checking docker networks .."
fi

if [ -z "$DOCKER_PLATFORM_HOME" ]; then
    echo "DOCKER_PLATFORM_HOME must be set"
    exit 1
fi

NETWORKS_CONFIG="$DOCKER_PLATFORM_HOME/etc/networks.conf"

if [ ! -f $NETWORKS_CONFIG ]; then
    echo "$DOCKER_PLATFORM_HOME/etc/networks.conf does not exist"
    exit 1
fi

source $NETWORKS_CONFIG

for NETWORK in "${NETWORKS[@]}"
do
    ACTIVE_NETWORK=$(docker network ls | grep $NETWORK)
    if [ -z "$ACTIVE_NETWORK" ]; then
        echo "Creating network '$NETWORK' .."
        RET=$(docker network create $NETWORK)
        if [ "$?" -ne 0 ]; then
            echo $RET
        fi
    fi
done

if [ ! $SCRIPT_DIR ]; then
    echo "Done!"
fi