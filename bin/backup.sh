#!/bin/bash
# Copyright (C) 2023 Alexander Wolz <mail@alexanderwolz.de>


function createPackagesBackup() {
    local BACKUP_ROOT=$1
    local PLATFORM_HOME=$2
    local PACKAGES_FOLDER="$PLATFORM_HOME/packages"
    local BACKUP_FOLDER="$BACKUP_ROOT/packages"

    mkdir -p "$BACKUP_FOLDER"

    for FOLDER in $PACKAGES_FOLDER/*/
    do
        PACKAGE=$(basename $FOLDER)
        tar cfz $BACKUP_FOLDER/$PACKAGE.tar.gz -C $FOLDER .
    done

    if [ "$?" -ne 0 ]; then
        echo "[WARN] Could not copy docker packages -> backing up anyway .."
    else
        SIZE=$(ls $BACKUP_FOLDER | wc -l)
        echo "Successfully copied $SIZE docker packages"
    fi
}

function createEnvBackup() {
    local BACKUP_ROOT=$1
    local PLATFORM_HOME=$2

    local ENV_FOLDER="$PLATFORM_HOME/env"
    local BACKUP_FOLDER="$BACKUP_ROOT/env"

    mkdir -p "$BACKUP_FOLDER"

    for FILE in $ENV_FOLDER/*.env
    do
        ENV=$(basename $FILE)
        tar cfz $BACKUP_FOLDER/$ENV.tar.gz -C $ENV_FOLDER $ENV
    done

    if [ "$?" -ne 0 ]; then
        echo "[WARN] Could not copy env files -> backing up anyway .."
    else
        SIZE=$(ls $BACKUP_FOLDER | wc -l)
        echo "Successfully copied $SIZE env files"
    fi
}

function createLogsBackup() {
    local BACKUP_ROOT=$1
    local PLATFORM_HOME=$2

    local BACKUP_FOLDER="$BACKUP_ROOT/logs"
    mkdir -p "$BACKUP_FOLDER"

    local ALL_CONTAINERS="$(docker ps -a --format {{.Names}})"

    for CONTAINER in $ALL_CONTAINERS
    do
        docker logs $CONTAINER 2>&1 | gzip > $BACKUP_FOLDER/$CONTAINER.log.gz
    done

    if [ "$?" -ne 0 ]; then
        echo "[WARN] Could not copy log files -> backing up anyway .."
    else
        SIZE=$(ls $BACKUP_FOLDER | wc -l)
        echo "Successfully backed up $SIZE log files"
    fi
}

function createPostgresBackups() {

    local BACKUP_ROOT=$1

    if [ -z "$POSTGRES_SERVERS" ]; then
        POSTGRES_SERVERS=($(docker ps -a | grep postgres | awk '{ print $11 }'))
    else
        IFS=', ' read -r -a POSTGRES_SERVERS <<< "$POSTGRES_SERVERS"
    fi

    if [ -z "$POSTGRES_SERVERS" ]; then
        echo "No postgres containers found"
    else
        for POSTGRES_SERVER in "${POSTGRES_SERVERS[@]}"
        do
            createPostgresBackup $BACKUP_ROOT $POSTGRES_SERVER
        done
    fi
}

function createPostgresBackup() {

    local BACKUP_ROOT=$1
    local POSTGRES_SERVER=$2
    local BACKUP_FOLDER="$BACKUP_ROOT/postgres/$POSTGRES_SERVER"

    mkdir -p "$BACKUP_FOLDER"

    #TODO: exception handling

    local DB_USER=$(docker exec $POSTGRES_SERVER bash -c 'echo "$POSTGRES_USER"')
    if [ ! $DB_USER ]; then
        local DB_USER="postgres"
    fi

    local DATABASES=($(docker exec $POSTGRES_SERVER /usr/local/bin/psql -U $DB_USER -d postgres -t -A -c "SELECT datname FROM pg_database WHERE datname <> ALL ('{template0,template1,postgres}')"))

    for DATABASE in "${DATABASES[@]}"
    do
        echo "Backing up database '$DATABASE' of container '$POSTGRES_SERVER' .."
        docker exec $POSTGRES_SERVER /usr/local/bin/pg_dump -U $DB_USER -F p $DATABASE | gzip -9 > $BACKUP_FOLDER/"$DATABASE".sql.gz
    done
}

function createMySqlBackups() {

    local BACKUP_ROOT=$1

    if [ -z "$MYSQL_SERVERS" ]; then
        MYSQL_SERVERS=($(docker ps -a | grep -h "mariadb\|mysql" | awk '{ print $12 }'))
    else
        IFS=', ' read -r -a MYSQL_SERVERS <<< "$MYSQL_SERVERS"
    fi

    if [ -z "$MYSQL_SERVERS" ]; then
        echo "No Mariadb/MySQL containers found"
    else
        for MYSQL_SERVER in "${MYSQL_SERVERS[@]}"
        do
            createMySqlBackup $BACKUP_ROOT $MYSQL_SERVER
        done
    fi
}

function createMySqlBackup() {

    local BACKUP_ROOT=$1
    local MYSQL_SERVER=$2
    local BACKUP_FOLDER="$BACKUP_ROOT/mysql/$MYSQL_SERVER"

    mkdir -p "$BACKUP_FOLDER"

    #TODO: exception handling

    local ROOT_PW=$(docker exec $MYSQL_SERVER bash -c 'echo "$MARIADB_ROOT_PASSWORD"')
    if [ ! $ROOT_PW ]; then
        # lookup mysql root password
        local ROOT_PW=$(docker exec $MYSQL_SERVER bash -c 'echo "$MYSQL_ROOT_PASSWORD"')
    fi

    if [ ! $ROOT_PW ]; then
        local DATABASES=($(docker exec $MYSQL_SERVER /usr/bin/mysql -uroot -N -e 'show databases'))
    else
         local DATABASES=($(docker exec $MYSQL_SERVER /usr/bin/mysql -uroot -p$ROOT_PW -N -e 'show databases'))
    fi
    
    for DATABASE in "${DATABASES[@]}"
    do
        if [ ! "$DATABASE" = "information_schema" ] && [ ! "$DATABASE" = "mysql" ] && [ ! "$DATABASE" = "sys" ] && [ ! "$DATABASE" = "performance_schema" ]; then
            echo "Backing up database '$DATABASE' of container '$MYSQL_SERVER' .."
            if [ ! $ROOT_PW ]; then
                docker exec $MYSQL_SERVER /usr/bin/mysqldump -uroot --complete-insert --routines --triggers --single-transaction "$DATABASE" | gzip -9 > $BACKUP_FOLDER/"$DATABASE".sql.gz
            else
                docker exec $MYSQL_SERVER /usr/bin/mysqldump -uroot -p$ROOT_PW --complete-insert --routines --triggers --single-transaction "$DATABASE" | gzip -9 > $BACKUP_FOLDER/"$DATABASE".sql.gz
            fi
        fi
    done
}


function createVolumeBackup() {

    local BACKUP_ROOT=$1
    local VOLUME=$2
    local BACKUP_FOLDER="$BACKUP_ROOT/volumes"
    local MYSQL_LIB_DESTINATION="/var/lib/mysql"
    local POSTGRES_LIB_DESTINATION="/var/lib/postgresql/data"

    local CONTAINERS=$(docker ps -a --filter=volume=$VOLUME --format '{{.Names}}')

    if [ -n "$CONTAINERS" ]; then 
       
        #check if mysql lib data - we backup sql dumps, so skip this
        for CONTAINER in "${CONTAINERS[@]}"
        do
            local DESTINATION=$(docker inspect --format "{{ range .Mounts }}{{ if eq .Name \"$VOLUME\" }}{{ .Destination }}{{ end }}{{ end }}" $CONTAINER)
            if [ "$DESTINATION" = "$MYSQL_LIB_DESTINATION" ]; then
                echo "Backing up volume '$VOLUME' skipped (MySQL dump)"
                return 0
            fi
            if [ "$DESTINATION" = "$POSTGRES_LIB_DESTINATION" ]; then
                echo "Backing up volume '$VOLUME' skipped (Postgres dump)"
                return 0
            fi
        done

        for CONTAINER in "${CONTAINERS[@]}"
        do
            docker stop $CONTAINER > /dev/null
            if [ "$?" -ne 0 ]; then
                echo "[WARN] Could not stop $CONTAINER -> backing up anyway .."
            fi
        done
    fi

    echo "Backing up volume '$VOLUME' .."
    docker run --name backup_helper --rm -v $VOLUME:/volume -v $BACKUP_FOLDER:/backups $HELPER_IMAGE sh -c "tar cfz /backups/$VOLUME.tar.gz -C /volume . && chown -R $USER:$GROUP /backups/$VOLUME.tar.gz"
}

function createVolumeBackups(){
    local BACKUP_ROOT=$1
    VOLUMES=($(docker volume ls --format '{{.Name}}'))
    for VOLUME in "${VOLUMES[@]}"
    do
        if [[ $VOLUME != buildx_buildkit* ]]; then
            createVolumeBackup $BACKUP_ROOT $VOLUME
        fi
    done
}


function createBackup() {

    echo "" # newline
    echo "---------------------------------------------------------------"
    echo "Executing backup script at $(date)"

    # --- packages backups --- #
    echo "---------------------------------------------------------------"
    echo "Backing up Docker packages"
    createPackagesBackup $BACKUP_ROOT $DOCKER_PLATFORM_HOME

    # --- env backup --- #
    echo "---------------------------------------------------------------"
    echo "Backing up env files "
    createEnvBackup $BACKUP_ROOT $DOCKER_PLATFORM_HOME

    # --- logs backup --- #
    echo "---------------------------------------------------------------"
    echo "Backing up log files "
    createLogsBackup $BACKUP_ROOT $DOCKER_PLATFORM_HOME

    # --- mysql dumps --- #
    echo "---------------------------------------------------------------"
    echo "Backing up Mariadb/MySQL dumps"
    createMySqlBackups $BACKUP_ROOT

    # --- postgres dumps --- #
    echo "---------------------------------------------------------------"
    echo "Backing up Postgres dumps"
    createPostgresBackups $BACKUP_ROOT

    # --- get all running containers --- #
    RUNNING_CONTAINERS=($(docker ps --format "{{.Names}}"))

    # --- volume backups --- #
    echo "---------------------------------------------------------------"
    echo "Backing up Docker volumes"
    createVolumeBackups $BACKUP_ROOT

    # --- restart containers --- #
    echo "---------------------------------------------------------------"
    echo "restarting all previously running containers again .."
    for CONTAINER in "${RUNNING_CONTAINERS[@]}"
    do
        # start containers in background
        docker start $CONTAINER >/dev/null &
    done

    # --- Setting final permissions and timestamp --- #
    echo "---------------------------------------------------------------"
    echo "Setting final permissions and timestamp .."
    echo $NOW > "$BACKUP_ROOT/.timestamp"
    chown -R $USER:$GROUP $BACKUP_ROOT
    find $BACKUP_ROOT -type d -exec chmod 750 '{}' \;
    find $BACKUP_ROOT -type f -exec chmod 640 '{}' \;

    echo "---------------------------------------------------------------"
    echo "Finished creating backup content at $(date)"
}









##                                              ##
##  ------    EXECUTION STARTS HERE  ---------  ##
##                                              ##

BEGIN=$(date -u +%s)
NOW=$(date +"%Y%m%d_T%H%M%S")

if ! [ $(id -u) = 0 ]; then
    echo "Must run as root user"
    exit 1
fi

if [ ! -f /.dockerenv ]; then
    #not run from docker environment
    #workaround to read env variables of user root if sudo is done
    source /root/.profile
fi

if [ -z "$DOCKER_PLATFORM_HOME" ]; then
    echo "DOCKER_PLATFORM_HOME must be set"
    exit 1
fi


if [ -z "$DOCKER_PLATFORM_BACKUPS" ]; then
    echo "DOCKER_PLATFORM_BACKUPS must be set"
    exit 1
fi

declare -a OPTIONS=()
while getopts i? opt; do
    case $opt in
    i)
        NOT_INTERACTIVE=1
        ;;
    esac
done

if [  -z "$NOT_INTERACTIVE" ]; then 
    #run interactively
    while true; do
        read -p "Do you wish to backup all packages? [y/n] " selection
            case $selection in
            [y]*) break ;;
            [n]*) exit ;;
            *) echo "Please answer y or n." ;;
        esac
    done
fi

BACKUP_ROOT="$DOCKER_PLATFORM_BACKUPS/$NOW"
LOG_FILE="$BACKUP_ROOT/.log"
LATEST_FOLDER="$DOCKER_PLATFORM_BACKUPS/latest"
BACKUP_EXTENSION="tar.gz"
BACKUP_ZIP="$BACKUP_ROOT.$BACKUP_EXTENSION"
HELPER_IMAGE="alpine:3.17.2"
USER=1000
GROUP=1000

mkdir -p $BACKUP_ROOT && chown $USER:$GROUP $BACKUP_ROOT

createBackup 2>&1 | tee $LOG_FILE

#log this only to the logfile
echo "---------------------------------------------------------------"  >> $LOG_FILE 
echo "" >> $LOG_FILE  #newline



# --- Put everything into one big tar ball --- #
echo "---------------------------------------------------------------"
echo "Compressing.."
pushd $BACKUP_ROOT > /dev/null
tar czf $BACKUP_ZIP .  > /dev/null
if [ "$?" -ne 0 ]; then
    echo "Error while compressing the backup file"
fi
popd > /dev/null
chown -R $USER:$GROUP $BACKUP_ZIP
chmod -R 640 $BACKUP_ZIP



# --- Clean Up, link latest backup files--- #
echo "---------------------------------------------------------------"
echo "Cleanup.."
rm -rf $LATEST_FOLDER
mv $BACKUP_ROOT $LATEST_FOLDER

# --- Remove files older than 5 days --- #
find $DOCKER_PLATFORM_BACKUPS -type f -mtime +5 -name "*.$BACKUP_EXTENSION" | xargs rm -rf



duration=$(($(date -u +%s)-$BEGIN))
echo "---------------------------------------------------------------"
echo "Timestamp $(date)"
echo "Finished Backup - took $(($duration / 60)) minutes and $(($duration % 60)) seconds"
echo "---------------------------------------------------------------"
echo "" #newline
