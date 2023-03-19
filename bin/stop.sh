#!/bin/bash
# Copyright (C) 2023 Alexander Wolz <mail@alexanderwolz.de>


function doStop(){

    loadPackageFromArgs $1
    if [ "$?" -ne 0 ]; then
        return 1
    fi

    echo "Stopping Package: '$NAME'"

    COMMAND="--remove-orphans"
    if [ $DELETE_VOLUMES ]; then
        COMMAND+=" -v"
    fi

    if [ -f $ENV_FILE ]; then
        echo "Using env file: $ENV_FILE"
    fi

    #TODO: only restart or tear down and up again?
    echo "Tearing down compose.."
    if [ -f $ENV_FILE ]; then
        docker-compose -p $NAME -f $COMPOSE_FILE --env-file $ENV_FILE down $COMMAND
    else
        docker-compose -p $NAME -f $COMPOSE_FILE down $COMMAND
    fi
    if [ "$?" -ne 0 ]; then
        echo "Error while stopping compose.."
        return 1
    fi

    if [ "$?" -ne 0 ]; then
        return 1
    fi
}

### ---- INIT ---- ###

if [ -z "$DOCKER_PLATFORM_HOME" ]; then
    echo "DOCKER_PLATFORM_HOME must be set"
    exit 1
fi

while getopts v opt; do
    case $opt in
    v)
        DELETE_VOLUMES=1
        ;;
    esac
done

shift $((OPTIND - 1))
[ "${1:-}" = "--" ] && shift


CURRENT_DIR=$PWD
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

. $SCRIPT_DIR/common.sh
if [ "$?" -ne 0 ]; then
    exit 1
fi

docker ps -q >/dev/null
if [ "$?" -ne 0 ]; then
    exit 1
fi

doStop $1

echo "Finished stop script!"
