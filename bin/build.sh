#!/bin/bash
# Copyright (C) 2023 Alexander Wolz <mail@alexanderwolz.de>


function printHelpMenu(){
    echo ""
    echo "Docker Build Script"
    echo "----------------------------"
    echo "  -a build for current arch"
    echo "  -e pull existing image"
    echo "  -l tag as lates"
    echo "  -p push image to registry"
    echo "  -r rebuild existing image"
    echo "----------------------------"
    echo "  -h print this menu"
    echo ""
}

##                          ##
##  ------  START --------- ##
##                          ##

#  builds any project with Dockerfile
#   - Gradle projecs
#   - Maven projects (TBD)
#   - NPM projects

CURRENT_FILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

PARENT_DIR="$(dirname $CURRENT_FILE_DIR)"
LOCAL_CONFIG_DIR="$PARENT_DIR/config"
REGISTRY_CONFIG="$LOCAL_CONFIG_DIR/registry.conf"

. $REGISTRY_CONFIG >/dev/null 2>&1
if [ "$?" -ne 0 ]; then
    echo "Please create '$REGISTRY_CONFIG' before using this script!"
    exit 1
fi

if [ -z "$DOCKER_REGISTRY" ]; then
    echo "Could not retrieve DOCKER_REGISTRY from '$REGISTRY_CONFIG', please check file"
    exit 1
fi


while getopts aelprh opt; do
    case $opt in
    h)
        printHelpMenu
        exit 0
        ;;
    a)
        CURRENT_ARCH=1
        ;;
    e)
        PULL_EXISTING=1
        ;;
    l)
        TAG="latest"
        ;;
    p)
        PUSH_IMAGE=1
        ;;
    r)
        REBUILD=1
        ;;
    esac
done

shift $((OPTIND - 1))
[ "${1:-}" = "--" ] && shift

if [ "$#" -lt 1 ]; then
    echo ""
    echo "usage: build.sh [-aelprh] folder"
    printHelpMenu
    exit 1
fi

BUILD_FOLDER=$1
BUILD_TYPE="generic"
DOCKER_FILE=$BUILD_FOLDER/Dockerfile
NPM_PACKAGE=$BUILD_FOLDER/package.json
MVN_PACKAGE=$BUILD_FOLDER/pom.xml
GRADLE_PACKAGE=$BUILD_FOLDER/build.gradle
GRADLE_KOTLIN_PACKAGE=$GRADLE_PACKAGE.kts

if [ ! -d $BUILD_FOLDER ]; then
    echo "$BUILD_FOLDER is not a folder"
    exit 1
fi

if [ ! -f $DOCKER_FILE ]; then
    echo "Folder does not contain Dockerfile"
    exit 1
fi

if [ -f $NPM_PACKAGE ]; then
    BUILD_TYPE="Node"
    IMAGE_NAME=$(grep '"name":' $NPM_PACKAGE | cut -d\" -f4)
    VERSION=$(grep '"version":' $NPM_PACKAGE | cut -d\" -f4)
fi

if [ -f $MVN_PACKAGE ]; then
    BUILD_TYPE="Maven"
    IMAGE_NAME=$(cat $MVN_PACKAGE | grep "^    <artifactId>.*</artifactId>$" | awk -F'[><]' '{print $3}')
    VERSION=$(cat $MVN_PACKAGE | grep "^    <version>.*</version>$" | awk -F'[><]' '{print $3}')
fi

if [ -f $GRADLE_PACKAGE ]; then
    BUILD_TYPE="Gradle"
    SETTINGS=$BUILD_FOLDER/settings.gradle
    IMAGE_NAME=$(grep 'rootProject.name' $SETTINGS | cut -d\' -f2)
    VERSION=$(grep 'version =' $GRADLE_PACKAGE | cut -d\' -f2)
fi

if [ -f $GRADLE_KOTLIN_PACKAGE ]; then
    BUILD_TYPE="Gradle"
    SETTINGS=$BUILD_FOLDER/settings.gradle.kts
    IMAGE_NAME=$(grep 'rootProject.name' $SETTINGS | cut -d\" -f2)
    VERSION=$(grep 'version =' $GRADLE_KOTLIN_PACKAGE | cut -d\" -f2)
fi


if [ -z "$IMAGE_NAME" ]; then
    echo "Could not retrieve image name from $BUILD_TYPE project, aborting.."
    exit 1
fi

if [ -z "$VERSION" ]; then
    echo "Could not retrieve version from $BUILD_TYPE project, aborting.."
    exit 1
fi

if [ -z "$TAG" ]; then
    TAG=$VERSION
fi

TARGET_NAME="$DOCKER_REGISTRY/$IMAGE_NAME:$TAG"

echo "Building $BUILD_TYPE project: $IMAGE_NAME v$VERSION (TAG: $TAG)"

docker ps -q >/dev/null 2>&1 # check if docker is running
if [ "$?" -ne 0 ]; then
    echo "Docker engine is not running!"
    exit 1
fi

if [[ $TAG != "latest" && $TAG != "0.0.0" ]]; then
    #check if tag already exists in registry
    docker login $DOCKER_REGISTRY >/dev/null 2>&1
    if [ "$?" -ne 0 ]; then
        echo "Could not login to registry"
        exit 1
    fi
    docker manifest inspect $TARGET_NAME >/dev/null 2>&1
    if [ "$?" -eq 0 ]; then
        if [ -z "$REBUILD" ]; then
            echo "Image with tag '$TAG' already exists in registry, skipping build."
            docker image inspect $TARGET_NAME >/dev/null 2>&1
            if [ "$?" -ne 0 ]; then
                if [ -z "$PULL_EXISTING" ]; then
                    echo "Image does not exist locally, use -e to pull from registry."
                else
                    echo "Image does not exist locally, pulling.."
                    docker pull $TARGET_NAME >/dev/null 2>&1
                    if [ "$?" -ne 0 ]; then
                        exit 1
                    fi
                    echo "Successfully pulled image."
                fi
            fi
            exit 0
        fi
    fi
fi

BEGIN=$(date +%s)


if [ ! -z "$CURRENT_ARCH" ]; then
    echo "Bulding for $(uname -m)"
    docker build -t $TARGET_NAME $BUILD_FOLDER
    if [ "$?" -ne 0 ]; then
        echo "[ERROR] Docker build unsuccessful!"
        exit 1
    fi
    if [[ $TAG != "latest" && $TAG != "0.0.0" ]]; then
        echo "pushing image to $TARGET_NAME"
        docker push $TARGET_NAME
    fi
    if [ "$?" -ne 0 ]; then
        echo "[ERROR] Docker push unsuccessful!"
        exit 1
    fi
else
    #multiarch builds
    echo "Creating buildx container.."
    BUILDER_NAME="multiarch"
    docker buildx rm $BUILDER_NAME > /dev/null
    docker buildx create --platform "linux/amd64,linux/arm64" --name $BUILDER_NAME --use > /dev/null
    OPTIONS=""
    if [ ! -z "$PUSH_IMAGE" ]; then
        if [[ $TAG != "latest" && $TAG != "0.0.0" ]]; then
            echo "Setting push to $TARGET_NAME"
            OPTIONS+="--push"
        else
            echo "Skipped push (invalid tag)"
        fi
    fi
    echo "Building image for amd64 and arm64 (host: $(uname -m)).."
    docker buildx build --platform linux/amd64,linux/arm64 $OPTIONS -t $TARGET_NAME $BUILD_FOLDER
    if [ "$?" -ne 0 ]; then
        echo "[ERROR] Docker command unsuccessful!"
        docker buildx rm $BUILDER_NAME > /dev/null
        exit 1
    fi
    echo "Cleaning up buildx container.."
    docker buildx rm $BUILDER_NAME > /dev/null
fi

BUILD_TIME=$(($(date +%s) - $BEGIN))
echo "Successfully built docker container in $BUILD_TIME seconds."
