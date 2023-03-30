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

function createPostgresBackup() {

    local BACKUP_ROOT=$1
    local POSTGRES_SERVER=$2
    local BACKUP_FOLDER="$BACKUP_ROOT/postgres/$POSTGRES_SERVER"

    mkdir -p "$BACKUP_FOLDER"

    #TODO: exception handling

    local USER=$(docker exec $POSTGRES_SERVER bash -c 'echo "$POSTGRES_USER"')
    if [ ! $USER ]; then
        local USER="postgres"
    fi

    local DATABASES=($(docker exec $POSTGRES_SERVER /usr/local/bin/psql -U $USER -d postgres -t -A -c "SELECT datname FROM pg_database WHERE datname <> ALL ('{template0,template1,postgres}')"))

    for DATABASE in "${DATABASES[@]}"
    do
        echo "Backing up database '$DATABASE' of container '$POSTGRES_SERVER' .."
        docker exec $POSTGRES_SERVER /usr/local/bin/pg_dump -U $USER -F p $DATABASE | gzip -9 > $BACKUP_FOLDER/"$DATABASE".sql.gz
    done
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

        echo "stopping linked containers of volume '$VOLUME'  .."
        for CONTAINER in "${CONTAINERS[@]}"
        do
            docker stop $CONTAINER > /dev/null
            if [ "$?" -ne 0 ]; then
                echo "[WARN] Could not stop $CONTAINER -> backing up anyway .."
            fi
        done
    fi

    echo "Backing up volume '$VOLUME' .."
    docker run --name backup_helper --rm -v $VOLUME:/volume -v $BACKUP_FOLDER:/backups $HELPER_IMAGE sh -c "tar cfz /backups/$VOLUME.tar.gz -C /volume . && chown -R 1000:1000 /backups/$VOLUME.tar.gz"
}





##                                              ##
##  ------    EXECUTION STARTS HERE  ---------  ##
##                                              ##

if ! [ $(id -u) = 0 ]; then
    echo "Must run as root"
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

NOW=$(date +"%Y%m%d_T%H%M%S")
BACKUP_ROOT="$DOCKER_PLATFORM_BACKUPS/$NOW"
BACKUP_TAR="$BACKUP_ROOT.tar.gz"
HELPER_IMAGE="alpine:3.17.2"

mkdir -p $BACKUP_ROOT
chown backup:backup -R $BACKUP_ROOT


echo "" # newline
echo "---------------------------------------------------------------"
echo "Executing backup script at $(date)"

BEGIN=$(date -u +%s)




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
        echo "Database Server: $MYSQL_SERVER"
        createMySqlBackup $BACKUP_ROOT $MYSQL_SERVER
    done
fi



# --- postgres dumps --- #
echo "---------------------------------------------------------------"
echo "Backing up Postgres dumps"

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
        echo "Database Server: $POSTGRES_SERVER"
        createPostgresBackup $BACKUP_ROOT $POSTGRES_SERVER
    done
fi



# --- volume backups --- #
echo "---------------------------------------------------------------"
echo "Backing up Docker volumes"

#get all running containers
RUNNING_CONTAINERS=($(docker ps --format "{{.Names}}"))

VOLUMES=($(docker volume ls --format '{{.Name}}'))
for VOLUME in "${VOLUMES[@]}"
do
    if [[ $VOLUME != buildx_buildkit* ]]; then
        createVolumeBackup $BACKUP_ROOT $VOLUME
    fi
done


# --- restart containers --- #
echo "---------------------------------------------------------------"
echo "restarting all previously running containers again .."
for CONTAINER in "${RUNNING_CONTAINERS[@]}"
do
    # start containers in background
    docker start $CONTAINER >/dev/null &
done



# --- Put everything into one big tar ball --- #
echo "---------------------------------------------------------------"
echo "Compressing.."
CURRENT_DIR=$PWD
chown -R backup:backup $BACKUP_ROOT
find $BACKUP_ROOT -type d -exec chmod 750 '{}' \;
find $BACKUP_ROOT -type f -exec chmod 640 '{}' \;
cd $BACKUP_ROOT
tar czf $BACKUP_TAR .
cd $CURRENT_DIR
chown -R backup:backup $BACKUP_TAR
find $BACKUP_TAR -type d -exec chmod 750 '{}' \;
find $BACKUP_TAR -type f -exec chmod 640 '{}' \;



# --- Clean Up, link latest backup files--- #
echo "---------------------------------------------------------------"
echo "Cleanup.."
LATEST_FOLDER="$DOCKER_PLATFORM_BACKUPS/latest"
rm -rf $LATEST_FOLDER
mv $BACKUP_ROOT $LATEST_FOLDER
echo $NOW > "$LATEST_FOLDER/.timestamp"
chown -R backup:backup "$LATEST_FOLDER/.timestamp"



# --- Remove files older than n days --- #
find $DOCKER_PLATFORM_BACKUPS -type f -mtime +5 -name '*tar.gz' | xargs rm -rf

duration=$(($(date -u +%s)-$BEGIN))

echo "---------------------------------------------------------------"
echo "Timestamp $(date)"
echo "Done - took $(($duration / 60)) minutes and $(($duration % 60)) seconds"
echo "---------------------------------------------------------------"
echo "" #newline
