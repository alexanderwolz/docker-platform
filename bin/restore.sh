#!/bin/bash
# Copyright (C) 2023 Alexander Wolz <mail@alexanderwolz.de>


function restorePackageFolder() {
    local PACKAGE_NAME=$1
    local PACKAGE_ZIP="packages/$PACKAGE_NAME.tar.gz"

    echo "Restoring local package folder '$PACKAGE_NAME'"

    pushd $TMP_FOLDER > /dev/null
    # extract package zip
    tar -zxf $BACKUP_FILE "./$PACKAGE_ZIP"
    popd > /dev/null

    if [ -f "$TMP_FOLDER/$PACKAGE_ZIP" ]; then
        local LOCAL_PGK_DIR="$PARENT_DIR/packages/$PACKAGE_NAME"
        rm -rf $LOCAL_PGK_DIR
        mkdir -p $LOCAL_PGK_DIR
        echo "Extracting package content to $LOCAL_PGK_DIR"
        tar -zxf "$TMP_FOLDER/$PACKAGE_ZIP" -C $LOCAL_PGK_DIR
        chown -R 1000:1000 $LOCAL_PGK_DIR
    else
        echo "Could not extract package zip $PACKAGE_ZIP!"
        return 1
    fi

}

function restoreEnvFile(){
    local PACKAGE_NAME=$1
    local ENV_FILE="env/$PACKAGE_NAME.env"
    local ENV_ZIP="$ENV_FILE.tar.gz"

    if [ -f "$PARENT_DIR/$ENV_FILE" ]; then
        now=$(date +"%Y%m%d")
        echo "Backing up existing env file for '$PACKAGE_NAME'"
        mv "$PARENT_DIR/$ENV_FILE" "$PARENT_DIR/$ENV_FILE.$now.bak"
    fi

    tar -tvf $BACKUP_FILE ./$ENV_ZIP >/dev/null 2>&1
    if [ "$?" -eq 0 ]; then
        echo "Restoring env file for '$PACKAGE_NAME'"
        
        pushd $TMP_FOLDER > /dev/null
        tar -zxf $BACKUP_FILE "./$ENV_ZIP"
        popd > /dev/null

        if [ -f "$TMP_FOLDER/$ENV_ZIP" ]; then
            tar -zxf "$TMP_FOLDER/$ENV_ZIP" -C "$PARENT_DIR/env"
        else
            echo "Could not extract env zip $ENV_ZIP!"
            return 1
        fi
    fi
}

function restore() {
    local BACKUP_FILE=$1
    local PACKAGE_NAME=$2
    local TMP_FOLDER="/backups/restore_tmp"

    if [ "$PWD" = "$TMP_FOLDER"* ]; then
        echo "Do not start this script from within $TMP_FOLDER! Exit"
        return 1
    fi

    BACKUP_FILE_CHECK="$BACKUP_FILE: gzip compressed data"
    if [[ ! $(file $BACKUP_FILE | grep "$BACKUP_FILE_CHECK") == *$BACKUP_FILE_CHECK* ]]; then
        echo "$BACKUP_FILE is not a regular backup file"
        return 1
    fi

    echo "---------------------------------------------------------------"
    echo "Timestamp: $(date)"
    echo "Restoring '$PACKAGE_NAME' with $BACKUP_FILE"
    echo "---------------------------------------------------------------"
    
    while true; do
        read -p "Do you wish to restore backup to $PACKAGE_NAME with $BACKUP_FILE? [y/n] " selection
            case $selection in
            [y]*) break ;;
            [n]*) exit ;;
            *) echo "Please answer y or n." ;;
        esac
    done

    rm -rf $TMP_FOLDER && mkdir -p $TMP_FOLDER

    echo "checking package file .."
    local PACKAGE_FOLDER="packages/$PACKAGE_NAME"
    local PACKAGE_ZIP="$PACKAGE_FOLDER.tar.gz"
    tar -tvf $BACKUP_FILE ./$PACKAGE_ZIP >/dev/null 2>&1
    if [ "$?" -ne 0 ]; then
        echo "Package is not part of that backup file, aborting.."
        rm -rf $TMP_FOLDER
        return 1
    fi

    echo "Checking local package folder.."
    loadPackageFromArgs $PACKAGE_NAME >/dev/null 2>&1
    local PACKAGE_EXISTS=$?

    #edge case: if package folder does not exist but the containers are started
    local VOLUME_DEPENDENCIES=()
    local HAS_ERROR=false
    local MYSQL_SERVERS=()
    local POSTGRES_SERVERS=()

    if [ $PACKAGE_EXISTS ]; then
        #shut down old service package containers first
        echo "Tearing down current package '$NAME' .."
        if [ -f $ENV_FILE ]; then
            docker compose -p $NAME -f $COMPOSE_FILE --env-file $ENV_FILE down --remove-orphans 
        else
            docker compose -p $NAME -f $COMPOSE_FILE down --remove-orphans
        fi
        if [ "$?" -ne 0 ]; then
            echo "Current package could not be stopped. Aborting"
            return 1
        fi

        echo "Removing existing volumes .."
        local VOLUME_NAMES=($(docker compose -f $COMPOSE_FILE config --volumes))

        for VOLUME_NAME in "${VOLUME_NAMES[@]}"
        do
            local VOLUME="$NAME"_"$VOLUME_NAME"
            docker volume rm $VOLUME >/dev/null 2>&1
            if [ "$?" -ne 0 ]; then
                echo "Volume $VOLUME could not be removed (dependencies?)"
                local BOUND_RUNNING_CONTAINER_IDS=($(docker ps -q --filter volume=$VOLUME))
                for CONTAINER_ID  in "${BOUND_RUNNING_CONTAINER_IDS[@]}"
                do
                    local PROJECT=$(docker inspect --format='{{index .Config.Labels "com.docker.compose.project"}}' $CONTAINER_ID)
                    if [ "$PROJECT" != "$NAME" ]; then
                        local CONTAINER_NAME=$(docker inspect --format '{{.Name}}' $CONTAINER_ID | cut -c2-)
                        VOLUME_DEPENDENCIES+=("$CONTAINER_NAME")
                    fi
                done
            fi
        done
        if [ ${#VOLUME_DEPENDENCIES[@]} -gt 0 ]; then
            echo "Stopping running volume dependencies, stopping .."
            for CONTAINER in "${VOLUME_DEPENDENCIES[@]}"
            do
                docker stop $CONTAINER
            done
        fi
    fi

    restorePackageFolder $PACKAGE_NAME
    if [ ! $PACKAGE_EXISTS ]; then
        loadPackageFromArgs $PACKAGE_NAME
        if [ "$?" -ne 0 ]; then
            echo "Error wile restoring package"
            rm -rf $TMP_FOLDER
            return 1
        fi
    fi

    #restore ENV files
    restoreEnvFile $NAME

    #create service containers and volumes
    echo "Creating containers and volumes for package '$NAME' .."
    if [ -f $ENV_FILE ]; then
        docker compose -p $NAME -f $COMPOSE_FILE --env-file $ENV_FILE up --no-start
    else
        docker compose -p $NAME -f $COMPOSE_FILE up --no-start
    fi
    local CONTAINER_IDS=($(docker compose -f $COMPOSE_FILE ps -q))
    if [[ ${#CONTAINER_IDS[@]} -eq 0 ]]; then
        echo "Compose does not have any containers, aborting"
        HAS_ERROR=true
    fi

    #restore volumes
    for CONTAINER_ID in "${CONTAINER_IDS[@]}"
    do  
        local CONTAINER=$(docker inspect --format="{{.Name}}" $CONTAINER_ID | cut -c2-)
        local VOLUMES=($(docker inspect --format="{{range .Mounts}}{{.Name}} {{end}}" $CONTAINER_ID))
        echo "---------------------------------------------------------------"
        echo "Restoring container '$CONTAINER'"

        if [[ ${#VOLUMES[@]} -eq 0 ]]; then
            echo -e "This container does not have any Docker volumes\n"
        fi

        for VOLUME in "${VOLUMES[@]}"
        do
            IMAGE_NAME=$(docker inspect --format="{{.Config.Image}}" $CONTAINER)
            if [[ $IMAGE_NAME == *"mariadb"* ]] || [[ $IMAGE_NAME == *"mysql"* ]]; then
                local MYSQL_LIB_DESTINATION="/var/lib/mysql"
                local DESTINATION=$(docker inspect --format "{{ range .Mounts }}{{ if eq .Name \"$VOLUME\" }}{{ .Destination }}{{ end }}{{ end }}" $CONTAINER)
                if [ "$DESTINATION" = "$MYSQL_LIB_DESTINATION" ]; then
                    MYSQL_SERVERS+=("$CONTAINER")
                    continue
                fi
            fi
            if [[ $IMAGE_NAME == *"postgres"* ]]; then
                local POSTGRES_LIB_DESTINATION="/var/lib/postgresql/data"
                local DESTINATION=$(docker inspect --format "{{ range .Mounts }}{{ if eq .Name \"$VOLUME\" }}{{ .Destination }}{{ end }}{{ end }}" $CONTAINER)
                if [ "$DESTINATION" = "$POSTGRES_LIB_DESTINATION" ]; then
                    POSTGRES_SERVERS+=("$CONTAINER")
                    continue
                fi
            fi 

            echo "---------------------------------------------------------------"
            echo "Restoring volume '$VOLUME'" 

            local PROJECT=$(docker volume inspect --format='{{index .Labels "com.docker.compose.project"}}' $VOLUME)
            if [ "$PROJECT" != "$NAME" ]; then
                echo "Ignoring volume '$VOLUME' because it is external. See package $PROJECT"
                continue
            fi   

            local VOLUME_ZIP="/volumes/$VOLUME.tar.gz"
            pushd $TMP_FOLDER > /dev/null
            tar -zxvf $BACKUP_FILE ".$VOLUME_ZIP"
            popd > /dev/null

            if [ -f "$TMP_FOLDER/$VOLUME_ZIP" ]; then
                #restore volume
                docker run --name backup_helper --rm -v $TMP_FOLDER:/backups -v $VOLUME:/volume alpine sh -c "cd /volume && rm -rf * && rm -rf .[a-zA-Z_-]* && tar zxf /backups/$VOLUME_ZIP --strip 1 && ls -lash /volume"
            else
                echo "[ERROR] No gzip file found for volume '$VOLUME' -> check backup file!"
                HAS_ERROR=true
            fi
            echo -e "Restored volume '$VOLUME'\n"

        done
    done

    if [[ ${MYSQL_SERVERS[@]} ]]; then
        echo "---------------------------------------------------------------"
        echo "We found MySQL/MariaDB instances, starting SQL restore process .."
        echo "---------------------------------------------------------------"
    fi

    for MYSQL_SERVER in "${MYSQL_SERVERS[@]}"
    do
        echo "Starting '$MYSQL_SERVER'"
        docker start $MYSQL_SERVER > /dev/null
        echo "Waiting some time for the container to come up.."
        sleep 7s

        local MYSQL_SERVER_FOLDER="mysql/$MYSQL_SERVER"

        pushd $TMP_FOLDER > /dev/null
        tar -zxvf $BACKUP_FILE "./$MYSQL_SERVER_FOLDER"
        popd > /dev/null
        if [ -d "$TMP_FOLDER/$MYSQL_SERVER_FOLDER" ]; then
            local ROOT_PW=$(docker exec $MYSQL_SERVER bash -c 'echo "$MARIADB_ROOT_PASSWORD"')
            if [ ! $ROOT_PW ]; then
                local ROOT_PW=$(docker exec $MYSQL_SERVER bash -c 'echo "$MYSQL_ROOT_PASSWORD"')
            fi
            #we need to iterate over all dump files
            for SQL_DUMP in $TMP_FOLDER/$MYSQL_SERVER_FOLDER/*.sql.gz; do
                DATABASE="$(basename "$SQL_DUMP" ".sql.gz")"
                echo "Restoring database '$DATABASE' for server '$MYSQL_SERVER'"
                if [ ! $ROOT_PW ]; then
                    gunzip -c $SQL_DUMP | docker exec -i $MYSQL_SERVER /usr/bin/mysql -uroot $DATABASE
                else
                    gunzip -c $SQL_DUMP | docker exec -i $MYSQL_SERVER /usr/bin/mysql -uroot -p$ROOT_PW $DATABASE
                fi
                 echo "Finished restoring database '$DATABASE' for server '$MYSQL_SERVER'"
            done
        else
            echo "no files found for mysql container '$MYSQL_SERVER' -> check backup file!"
            HAS_ERROR=true
        fi

    done




    if [[ ${POSTGRES_SERVERS[@]} ]]; then
        echo "---------------------------------------------------------------"
        echo "We found Postgres instances, starting SQL restore process .."
        echo "---------------------------------------------------------------"
    fi

    for POSTGRES_SERVER in "${POSTGRES_SERVERS[@]}"
    do
        echo "Starting '$POSTGRES_SERVER'"
        docker start $POSTGRES_SERVER > /dev/null
        echo "Waiting some time for the container to come up.."
        sleep 7s

        local POSTGRES_SERVER_FOLDER="postgres/$POSTGRES_SERVER"

        local USER=$(docker exec $POSTGRES_SERVER bash -c 'echo "$POSTGRES_USER"')
        if [ ! $USER ]; then
            local USER="postgres"
        fi

        pushd $TMP_FOLDER > /dev/null
        tar -zxvf $BACKUP_FILE "./$POSTGRES_SERVER_FOLDER"
        popd > /dev/null
        if [ -d "$TMP_FOLDER/$POSTGRES_SERVER_FOLDER" ]; then

            #we need to iterate over all dump files
            for SQL_DUMP in $TMP_FOLDER/$POSTGRES_SERVER_FOLDER/*.sql.gz; do
                DATABASE="$(basename "$SQL_DUMP" ".sql.gz")"
                echo "Restoring database '$DATABASE' for server '$POSTGRES_SERVER'"
                gunzip -c $SQL_DUMP | docker exec -i $POSTGRES_SERVER psql -U $USER -d $DATABASE
                echo "Finished restoring database '$DATABASE' for server '$POSTGRES_SERVER'"
            done

        else
            echo "no files found for postgres container '$POSTGRES_SERVER' -> check backup file!"
            HAS_ERROR=true
        fi


    done



    #start dependencies again
    if [ ${#VOLUME_DEPENDENCIES[@]} -gt 0 ]; then
        echo "---------------------------------------------------------------"
        echo "Starting previously stopped volume dependencies again .."
        for CONTAINER in "${VOLUME_DEPENDENCIES[@]}"
        do
            docker start $CONTAINER
        done
    fi
    
    #start package
    echo "---------------------------------------------------------------"
    echo "Starting $NAME again .."
    bash $SCRIPT_DIR/run.sh -bp $NAME
    echo "---------------------------------------------------------------"
 
    rm -rf $TMP_FOLDER

    if [ "$HAS_ERROR" = "true" ]; then
        return 1
    fi
    return 0
}


## ------------------------#
## ------ BEGIN -----------#

if ! [ $(id -u) = 0 ]; then
    echo "Must run as root"
    exit 1
fi

if [ -z "$DOCKER_PLATFORM_HOME" ]; then
    #workaround to read env variables of user root if sudo is done
    source /root/.profile
fi
if [ -z "$DOCKER_PLATFORM_HOME" ]; then
    echo "DOCKER_PLATFORM_HOME must be set"
    exit 1
fi

CURRENT_FILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PARENT_DIR="$(dirname $CURRENT_FILE_DIR)"
SCRIPT_DIR="$PARENT_DIR/bin"

. $SCRIPT_DIR/common.sh
if [ "$?" -ne 0 ]; then
    exit 1
fi


if [ "$#" -lt 2 ]; then
    echo "usage: restore.sh backup_file package_name"
    exit 1
fi
if [ "$#" -gt 2 ]; then
    echo "usage: restore.sh backup_file package_name"
    exit 1
fi

restore $1 $2
RC=$?
if [ "$RC" -eq 0 ]; then
    echo "Restore Script finished "
    echo "Please check env files if params are missing ($ENV_FILE)"
    echo "---------------------------------------------------------------"
fi

exit $RC