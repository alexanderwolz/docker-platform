#!/bin/bash
# Copyright (C) 2023 Alexander Wolz <mail@alexanderwolz.de>


FOLDER_NAME_PACKAGES="packages"
FOLDER_NAME_SCRIPTS="bin"
FOLDER_NAME_ENV="env"
FOLDER_NAME_ETC="etc"

FILE_NAME_PACKAGE_DESC="docker.pkd" # Package Definition file

KEY_COMPOSE_FILE="COMPOSE_FILE"
DEFAULT_COMPOSE_FILE="docker-compose.yml"

BASE_DIR="$(dirname "$SCRIPT_DIR")"
PACKAGES_DIR="$BASE_DIR/$FOLDER_NAME_PACKAGES"
ENV_DIR="$BASE_DIR/$FOLDER_NAME_ENV"
ETC_DIE="$BASE_DIR/$FOLDER_NAME_ETC"

function loadPackageFromArgs() {

  if [ "$#" -gt 1 ]; then
    echo "Error: Illegal number of parameters"
    return 1
  fi

  FOLDER=$1

  if [ -z $FOLDER ]; then
    echo "Error: please specify a package, e.g:"
    for directory in ls $PACKAGES_DIR/*/; do
      if [ -f "$directory$FILE_NAME_PACKAGE_DESC" ]; then
        echo "   - $(basename $directory)"
      fi
    done
    echo "   - package's root directory"
    return 1
  fi

  if [[ "${FOLDER}" == */ ]]; then
    FOLDER="${FOLDER::-1}"
  fi

  if [ ! -d "$FOLDER" ]; then
    # look up base package dir
    FOLDER="$PACKAGES_DIR/$FOLDER"
  fi

  if [ ! -d "$FOLDER" ]; then
    echo "Error: Invalid folder: '$FOLDER'"
    return 1
  fi

  ABSOLUTE_PACKAGE_FILE="$FOLDER/$FILE_NAME_PACKAGE_DESC"

  if [ ! -f "$ABSOLUTE_PACKAGE_FILE" ]; then
    echo "Error: Specified argument '$1' is not a compatible package."
    echo "See folder \"$ABSOLUTE_PACKAGE_FILE\""
    return 1
  fi

  source $ABSOLUTE_PACKAGE_FILE # source package variables

  if [ ! $COMPOSE_FILE ]; then
    COMPOSE_FILE=$DEFAULT_COMPOSE_FILE
  fi

  PACKAGE_FILES=("$FILE_NAME_PACKAGE_DESC" "$COMPOSE_FILE")

  if [ $PRE_HOOK ]; then
    PACKAGE_FILES+=("$PRE_HOOK")
  fi
  if [ $POST_HOOK ]; then
    PACKAGE_FILES+=("$POST_HOOK")
  fi
  if [ $ADDITIONAL_FILES ]; then
    TEMP=$ADDITIONAL_FILES
    unset ADDITIONAL_FILES
    IFS=', ' read -r -a ADDITIONAL_FILES <<<"$TEMP"
    for FILE in "${ADDITIONAL_FILES[@]}"; do
      PACKAGE_FILES+=("$FILE")
    done
  fi

  ABSOLUTE_PACKAGE_FILES=()
  for FILE in "${PACKAGE_FILES[@]}"; do
    #TODO ignore .-files
    ABSOLUTE_PACKAGE_FILES+=("$FOLDER/$FILE")
  done

  COMPOSE_FILE="$FOLDER/$COMPOSE_FILE"
  ENV_FILE="$ENV_DIR/$NAME.env"
  PRE_HOOK="$FOLDER/$PRE_HOOK"
  POST_HOOK="$FOLDER/$POST_HOOK"

}

function getComposeForPackage() {
  local SERVICE=$1
  local SERVICE_PACKAGE_FILE="$PACKAGES_DIR/$1/$FILE_NAME_PACKAGE_DESC"
  if [ -f $SERVICE_PACKAGE_FILE ]; then
    local SERVICE_COMPOSE_FILE=$(grep "^$KEY_COMPOSE_FILE=" $SERVICE_PACKAGE_FILE | cut -d"=" -f2 | tr -d '"')
    if [ ! $SERVICE_COMPOSE_FILE ]; then
      local SERVICE_COMPOSE_FILE=$DEFAULT_COMPOSE_FILE
    fi
    echo "$PACKAGES_DIR/$SERVICE/$SERVICE_COMPOSE_FILE"
  fi
}
