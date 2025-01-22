#!/bin/bash
# Copyright (C) 2023 Alexander Wolz <mail@alexanderwolz.de>


function printHelpMenu(){
    echo ""
    echo "Run Script"
    echo "----------------------------"
    echo "  -a run all packages"
    echo "  -b build container from source"
    echo "  -c no cache (only use with -b)"
    echo "  -p pull latest image"
    echo "  -t tear down"
    echo "  -v delete docker volumes"
    echo "----------------------------"
    echo "  -h print this menu"
    echo ""
}

function doRun(){

    loadPackageFromArgs $1
    if [ "$?" -ne 0 ]; then
        return 1
    fi

    echo "Running Package: '$NAME'"

    COMMAND="--remove-orphans"
    if [ $DELETE_VOLUMES ]; then
        COMMAND+=" -v"
    fi

    if [ -f $ENV_FILE ]; then
        echo "Using env file: $ENV_FILE"
    fi

    . $SCRIPT_DIR/bootstrap.sh

    if [ $TEAR_DOWN ]; then
        #TODO: only restart or tear down and up again?
        echo "Tearing down compose.."
        if [ -f $ENV_FILE ]; then
            docker compose -p $NAME -f $COMPOSE_FILE --env-file $ENV_FILE down $COMMAND
        else
            docker compose -p $NAME -f $COMPOSE_FILE down $COMMAND
        fi
        if [ "$?" -ne 0 ]; then
            echo "Error while stopping compose.."
            return 1
        fi
    fi

    if [ "$?" -ne 0 ]; then
        return 1
    fi

    if [ -f $PRE_HOOK ]; then
        echo "Executing Pre-Hook '$(basename $PRE_HOOK)'"
        . $PRE_HOOK
        if [ "$?" -ne 0 ]; then
            return 1
        fi
    fi

    if [ $BUILD ]; then
        if [ $BUILD_NO_CACHE ]; then
            echo "rebuilding images without cache .."
            if [ -f $ENV_FILE ]; then
                docker compose -p $NAME -f $COMPOSE_FILE --env-file $ENV_FILE build --no-cache
            else
                docker compose -p $NAME -f $COMPOSE_FILE build --no-cache
            fi
        else
            echo "rebuilding images .."
            if [ -f $ENV_FILE ]; then
                docker compose -p $NAME -f $COMPOSE_FILE --env-file $ENV_FILE build
            else
                docker compose -p $NAME -f $COMPOSE_FILE build
            fi
        fi

        if [ "$?" -ne 0 ]; then
            return 1
        fi
    fi

    if [ $PULL_IMAGE ]; then
        echo "pulling images .."
        if [ -f $ENV_FILE ]; then
            docker compose -p $NAME -f $COMPOSE_FILE --env-file $ENV_FILE pull
        else
            docker compose -p $NAME -f $COMPOSE_FILE pull
        fi

        if [ "$?" -ne 0 ]; then
            return 1
        fi
    fi

    echo "Starting up compose.."
    if [ -f $ENV_FILE ]; then
        docker compose -p $NAME -f $COMPOSE_FILE --env-file $ENV_FILE up -d
    else
        docker compose -p $NAME -f $COMPOSE_FILE up -d
    fi
    if [ "$?" -ne 0 ]; then
        echo "Error while starting up compose.."
        return 1
    fi

    if [ -f $POST_HOOK ]; then
        sleep 1s
        echo "Executing Post-Hook '$(basename $POST_HOOK)'"
        . $POST_HOOK
        if [ "$?" -ne 0 ]; then
            return 1
        fi
    fi
}

function runAll(){
    echo "Running all platform packages.."
    for PACKAGE in ls $PACKAGES_DIR/*; do
        if [ -f "$PACKAGE/$FILE_NAME_PACKAGE_DESC" ]; then
            echo "----------------------------"
            doRun $PACKAGE
        fi
    done
    echo "done"
}

### ---- INIT ---- ###

if [ -z "$DOCKER_PLATFORM_HOME" ]; then
    #workaround to source all env variables from profile.d
    source <(cat /etc/profile.d/*)
fi
if [ -z "$DOCKER_PLATFORM_HOME" ]; then
    #workaround to read env variables from current user
    source ~/.profile
fi
if [ -z "$DOCKER_PLATFORM_HOME" ]; then
    echo "DOCKER_PLATFORM_HOME must be set"
    exit 1
fi

while getopts abcpvth opt; do
    case $opt in
    a)
        RUN_ALL=1
        ;;
    b)
        BUILD=1
        ;;
    c)
        BUILD_NO_CACHE=1
        ;;
    p)
        PULL_IMAGE=1
        ;;
    v)
        DELETE_VOLUMES=1
        ;;
    t)
        TEAR_DOWN=1
        ;;
    h)
        printHelpMenu
        exit 0
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

if [ $RUN_ALL ]; then
    runAll
else
    doRun $1
fi

if [ "$?" -ne 0 ]; then
    echo "see -h for help and additional arguments"
    exit 1
fi

echo "Finished start script!"
