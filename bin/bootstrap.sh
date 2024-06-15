#!/bin/bash
# Copyright (C) 2024 Alexander Wolz <mail@alexanderwolz.de>


if [ -z $SCRIPT_DIR ]; then
    echo "Setting up docker networks and volumes .."
else
    echo "Checking docker networks and volumes .."
fi

if [ -z "$DOCKER_PLATFORM_HOME" ]; then
    echo "DOCKER_PLATFORM_HOME must be set"
    exit 1
fi

CONFIG_FILE="$DOCKER_PLATFORM_HOME/etc/bootstrap.conf"

if [ ! -f $CONFIG_FILE ]; then
    echo "$CONFIG_FILE does not exist"
    exit 1
fi

source $CONFIG_FILE

for NETWORK in "${NETWORKS[@]}"
do
    ACTIVE_NETWORK=$(docker network ls | grep $NETWORK)
    if [ -z "$ACTIVE_NETWORK" ]; then
        echo "Creating network '$NETWORK' .."
        RET=$(docker network create $NETWORK)
        if [ "$?" -ne 0 ]; then
            echo $RET
        fi
    else
        if [ -z $SCRIPT_DIR ]; then
            echo "  Network $NETWORK already exists, skipping"
        fi
    fi
done

for VOLUME in "${VOLUMES[@]}"
do
    ACTIVE_VOLUME=$(docker volume ls | grep $VOLUME)
    if [ -z "$ACTIVE_VOLUME" ]; then
        echo "Creating volume '$VOLUME' .."
        RET=$(docker volume create $VOLUME)
        if [ "$?" -ne 0 ]; then
            echo $RET
        fi
    else
        if [ -z $SCRIPT_DIR ]; then
            echo "  Volume $VOLUME already exists, skipping"
        fi
    fi
done

if [ ! $SCRIPT_DIR ]; then
    echo "Done!"
fi