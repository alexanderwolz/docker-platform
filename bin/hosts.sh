#!/bin/bash
# Copyright (C) 2023 Alexander Wolz <mail@alexanderwolz.de>


USER=$(whoami)

if ! [ $(id -u) = 0 ]; then
    echo "Must run as root"
    exit 1
fi

HOSTS_FILE="/etc/hosts"
TAG="#docker#"

function removeHost() {
    local HOSTNAME=$1
    local FOUND_LINES=$(grep $HOSTNAME $HOSTS_FILE)
    if [ ! -z "$FOUND_LINES" ]; then

        sed -i".bak" "/$HOSTNAME/d" $HOSTS_FILE

        FOUND_LINES=$(grep $HOSTNAME $HOSTS_FILE) #double check
        if [ ! -z "$FOUND_LINES" ]; then
            # did not work
            return 1
        fi
    fi
    return 0
}

function addHost() {
    local HOSTNAME=$1
    local IP=$2
    echo "$IP $HOSTNAME $TAG" >> $HOSTS_FILE

    local FOUND_LINES=$(grep $HOSTNAME $HOSTS_FILE)  # doublecheck
    if [ ! -z "$FOUND_LINES" ]; then
        echo "Updated '$CONTAINER_NAME' with IP: $IP"
        return 0
    fi
    return 1
}

function updateHost() {
    local CONTAINER_NAME=$1

    local HOSTNAME=$CONTAINER_NAME
    if [ -z "$HOSTNAME" ]; then
      echo "[ERROR] No Container name given, skipping"
      return 1
    fi
    
    local IPS=($(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' $CONTAINER_NAME))
    if [[ ${#IPS[@]} -eq 0 ]]; then
        echo "[ERROR] No IP's found for container $CONTAINER_NAME, skipping"
        return 1
    fi

    removeHost $HOSTNAME #remove existing entry
    if [ "$?" -ne 0 ]; then
        echo "[Error]: Could not remove entry for '$HOSTNAME'!"
        return 1
    fi

    for IP in "${IPS[@]}"
    do
        addHost "$HOSTNAME" "$IP"
        if [ "$?" -ne 0 ]; then
            echo "[ERROR] Failed to add '$HOSTNAME' with IP $IP";
        fi
    done
}

function deleteTaggedHosts() {
    echo "Deleting tagged docker host entries.."
    sed -i".bak" "/$TAG/d" $HOSTS_FILE
    FOUND_LINES=$(grep $TAG $HOSTS_FILE)  # doublecheck
    if [ ! -z "$FOUND_LINES" ]; then
        echo "[WARN] Could not remove (all) old docker host entrie"
    else
        echo "Successfully deleted all tagged docker host entries."
    fi
}

function cleanUpdate() {

    deleteTaggedHosts

    echo "Adding new tagged docker host entries.."
    ALL_CONTAINERS=($(docker ps --format '{{.Names}}'))
    for CONTAINER in "${ALL_CONTAINERS[@]}"
    do
        updateHost "$CONTAINER"
    done
}

### ------ INIT ------- ###

if [ "$1" = "clean" ]; then
    deleteTaggedHosts
    exit $?
fi

echo "started hosts script at $(date)"
echo "-------------------------------------------------------"
echo "Initializing running docker containers .."

cleanUpdate

echo "-------------------------------------------------------"
echo "Finished initialization, listening for docker events .."
echo "-------------------------------------------------------"