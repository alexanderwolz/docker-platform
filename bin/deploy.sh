#!/bin/bash
# Copyright (C) 2023 Alexander Wolz <mail@alexanderwolz.de>


function initialize() {
    while true; do
        echo ""
        echo "  INITIALIZATION MODE"
        echo ""
        echo "  Running containers and images will be deleted."
        echo "  Base folder '$REMOTE_BASE_FOLDER' and '$REMOTE_BACKUP_FOLDER' will be deleted!"
        echo "  Please consider taking local backups before execution!"
        echo ""
        read -p "Do you wish to initialize platform to $REMOTE_HOST? [y/n] " selection
        case $selection in
        [y]*)

            echo "-----------------------------------"
            echo "Stopping running containers"
            ssh $REMOTE $SSH_OPTS 'docker stop $(docker ps -aq) 2>/dev/null || echo "No running containers"'
            echo "Pruning docker engine (remove stopped and unused resources).."
            ssh $REMOTE $SSH_OPTS 'docker system prune -a -f'
            if [ "$?" -ne 0 ]; then
                exit 1
            fi

            echo "-----------------------------------"
            echo "Deleting base folders .."
            ssh $REMOTE $SSH_OPTS "rm -rf $REMOTE_BASE_FOLDER $REMOTE_BACKUP_FOLDER"
            if [ "$?" -ne 0 ]; then
                USER_ID=$(ssh $REMOTE $SSH_OPTS id -u)
                echo "trying again with super user:"
                ssh $REMOTE $SSH_OPTS -t "sudo rm -rf $REMOTE_BASE_FOLDER $REMOTE_BACKUP_FOLDER"
            fi
            if [ "$?" -ne 0 ]; then
                echo "Error: Could not delete base folders!"
                exit 1
            fi

            echo "-----------------------------------"
            echo "Creating base folders '$REMOTE_BASE_FOLDER' and '$REMOTE_BACKUP_FOLDER' .."
            ssh $REMOTE $SSH_OPTS "mkdir -p $REMOTE_BASE_FOLDER $REMOTE_BACKUP_FOLDER"
            if [ "$?" -ne 0 ]; then
                USER_ID=$(ssh $REMOTE $SSH_OPTS id -u)
                echo "trying again with super user:"
                ssh $REMOTE $SSH_OPTS -t "sudo mkdir -p $REMOTE_BASE_FOLDER $REMOTE_BACKUP_FOLDER && sudo chown $USER_ID:$USER_ID -R $REMOTE_BASE_FOLDER $REMOTE_BACKUP_FOLDER"
            fi
            if [ "$?" -ne 0 ]; then
                echo "Error: Could not create base folders!"
                exit 1
            fi

            echo "Creating subfolders in '$REMOTE_BASE_FOLDER' .."
            ssh $REMOTE $SSH_OPTS "mkdir -p $REMOTE_PACKAGES_FOLDER && mkdir -p $REMOTE_SCRIPTS_FOLDER && mkdir -p $REMOTE_ENV_FOLDER && mkdir -p $REMOTE_ETC_FOLDER"
            if [ "$?" -ne 0 ]; then
                echo "Error: Could not create remote folders!"
                exit 1
            fi

            echo "-----------------------------------"
            uploadEtcFolder
            if [ "$?" -ne 0 ]; then
                exit 1
            fi

            echo "-----------------------------------"
            uploadScripts
            if [ "$?" -ne 0 ]; then
                exit 1
            fi

            echo "-----------------------------------"
            ssh $REMOTE $SSH_OPTS "source ~/.profile && bash $REMOTE_SCRIPTS_FOLDER/networks.sh"
            if [ "$?" -ne 0 ]; then
                exit 1
            fi

            echo "-----------------------------------"
            echo "Platform basics are initialized."

            while true; do
                read -p "Do you wish to copy all packages? [y/n] " selection
                case $selection in
                [y]*)
                    ssh $REMOTE $SSH_OPTS "echo 'Add {PKG_NAME}.env into this folder to automatically use env file on startup' > $REMOTE_ENV_FOLDER/Readme.txt"

                    echo "-----------------------------------"
                    echo "Copying platform packages to '$REMOTE_PACKAGES_FOLDER' .."
                    rsync -avzPL -e "ssh $SSH_OPTS" $PACKAGES_DIR/* "$REMOTE:$REMOTE_PACKAGES_FOLDER"
                    if [ "$?" -ne 0 ]; then
                        exit 1
                    fi

                    echo "-----------------------------------"
                    echo "Creating symbolic links to environment files .."
                    for PACKAGE in ls $PACKAGES_DIR/*; do
                        if [ -f "$PACKAGE/$FILE_NAME_PACKAGE_DESC" ]; then
                        PKG_NAME=$(basename $PACKAGE)
                            ssh $REMOTE $SSH_OPTS "ln -sf $REMOTE_ENV_FOLDER/$PKG_NAME.env $REMOTE_PACKAGES_FOLDER/$PKG_NAME/.env"
                        fi
                    done

                    while true; do
                        read -p "Do you wish to start all packages? [y/n] " selection
                        case $selection in
                        [y]*)
                            ssh $REMOTE $SSH_OPTS "bash $REMOTE_SCRIPTS_FOLDER/run.sh -ta"
                            break
                            ;;
                        [n]*)
                            break
                            ;;
                        *) echo "Please answer y or n." ;;
                        esac
                    done

                    break
                    ;;
                [n]*)
                    break
                    ;;
                *) echo "Please answer y or n." ;;
                esac
            done

            echo "-----------------------------------"
            echo "Initializing was successful!"
            echo "-----------------------------------"
            exit 0
            ;;
        [n]*)
            exit 1
            ;;
        *) echo "Please answer y or n." ;;
        esac
    done
}

function uploadPackageFiles(){
    echo "Copying package files to '$REMOTE_PACKAGE_FOLDER'.."
    rsync -avzPL -e "ssh $SSH_OPTS" --delete ${ABSOLUTE_PACKAGE_FILES[*]} "$REMOTE:$REMOTE_PACKAGE_FOLDER"
    if [ "$?" -ne 0 ]; then
        exit 1
    fi
}

function createEnvLink(){
    ssh $REMOTE $SSH_OPTS "ln -sf $REMOTE_ENV_FOLDER/$NAME.env $REMOTE_PACKAGE_FOLDER/.env"
}

function createScriptsFolder(){
    echo "Creating script folder in '$REMOTE_BASE_FOLDER' .."
    ssh $REMOTE $SSH_OPTS "mkdir -p $REMOTE_SCRIPTS_FOLDER"
    if [ "$?" -ne 0 ]; then
        echo "Error: Could not create script folder!"
        exit 1
    fi
}

function uploadScripts(){
    echo "Copying scripts to '$REMOTE_SCRIPTS_FOLDER' .."
    rsync -avzPL -e "ssh $SSH_OPTS" $LOCAL_SCRIPTS "$REMOTE:$REMOTE_SCRIPTS_FOLDER"
}

function createEtcFolder(){
    echo "Creating etc folder in '$REMOTE_BASE_FOLDER' .."
    ssh $REMOTE $SSH_OPTS "mkdir -p $REMOTE_ETC_FOLDER"
    if [ "$?" -ne 0 ]; then
        echo "Error: Could not create etc folder!"
        exit 1
    fi
}

function uploadEtcFolder(){
    echo "Copying etc to '$REMOTE_ETC_FOLDER' .."
    rsync -avzPL -e "ssh $SSH_OPTS" $LOCAL_ETC_FILES "$REMOTE:$REMOTE_ETC_FOLDER"
}


function executeRun() {
    local COMMAND="t"
    if [ $DELETE_VOLUMES ];then
        COMMAND+="v"
    fi
    if [ $BUILD_FROM_SOURCE ];then
        COMMAND+="b"
    fi
    if [ $BUILD_WITHOUT_CACHE ];then
        COMMAND+="c"
    fi
    if [ $PULL_LATEST_IMAGE ];then
        COMMAND+="p"
    fi
    if [ $COMMAND ];then
        COMMAND="-"$COMMAND
    fi
    ssh $REMOTE $SSH_OPTS "bash $REMOTE_SCRIPTS_FOLDER/run.sh $COMMAND $NAME"
    if [ "$?" -ne 0 ]; then
        exit 1
    fi
}

function printHelpMenu(){
    echo ""
    echo "Platform Deployment Script"
    echo "----------------------------"
    echo "  -r auto-restart component"
    echo "  -b build container from source"
    echo "  -p pull latest image"
    echo "  -f skip package files upload"
    echo "  -v delete docker volumes"
    echo "----------------------------"
    echo "  -s copy scripts only"
    echo "  -e copy etc folder"
    echo "  -i initialize platform"
    echo "----------------------------"
    echo "  -h print this menu"
    echo ""
}

function getAndCheckConfig(){
    . $DEPLOY_CONFIG >/dev/null 2>&1
    if [ "$?" -ne 0 ]; then
        echo "Please create '$DEPLOY_CONFIG' before using this script!"
        exit 1
    fi

    if [ -e $REMOTE_HOST ]; then
        echo "Config does not contain REMOTE_HOST"
        exit 1
    fi

    if [ -e $REMOTE_USER ]; then
        echo "Config does not contain REMOTE_USER"
        exit 1
    fi

    if [ -e $REMOTE_PORT ]; then
        echo "Config does not contain REMOTE_PORT"
        exit 1
    fi
}

##                      ##
##  --- START HERE ---  ##
##                      ##

CURRENT_FILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

PARENT_DIR="$(dirname $CURRENT_FILE_DIR)"
SCRIPT_DIR="$PARENT_DIR/bin"
LOCAL_CONFIG_DIR="$PARENT_DIR/config"
DEPLOY_CONFIG="$LOCAL_CONFIG_DIR/deploy.conf"
LOCAL_ETC_FILES="$PARENT_DIR/etc/*"
LOCAL_SCRIPTS="$SCRIPT_DIR/armageddon.sh $SCRIPT_DIR/backup.sh $SCRIPT_DIR/common.sh $SCRIPT_DIR/hosts.sh $SCRIPT_DIR/networks.sh $SCRIPT_DIR/restore.sh $SCRIPT_DIR/run.sh $SCRIPT_DIR/stop.sh"

getAndCheckConfig

. $SCRIPT_DIR/common.sh
if [ "$?" -ne 0 ]; then
    exit 1
fi

REMOTE=$REMOTE_USER@$REMOTE_HOST 
if [ ! -e $REMOTE_KEY ]; then
    SSH_OPTS="-i $REMOTE_KEY  -p $REMOTE_PORT"
else
    SSH_OPTS="-p $REMOTE_PORT"
fi

REMOTE_BASE_FOLDER=$(ssh $REMOTE $SSH_OPTS 'source ~/.profile && echo $DOCKER_PLATFORM_HOME')
if [ -z $REMOTE_BASE_FOLDER ]; then
    echo "\$DOCKER_PLATFORM_HOME is not set on remote server"
    exit 1
fi

REMOTE_BACKUP_FOLDER=$(ssh $REMOTE $SSH_OPTS 'source ~/.profile && echo $DOCKER_PLATFORM_BACKUPS')
if [ -z $REMOTE_BASE_FOLDER ]; then
    echo "\$DOCKER_PLATFORM_BACKUPS is not set on remote server"
    exit 1
fi

REMOTE_PACKAGES_FOLDER="$REMOTE_BASE_FOLDER/$FOLDER_NAME_PACKAGES"
REMOTE_SCRIPTS_FOLDER="$REMOTE_BASE_FOLDER/$FOLDER_NAME_SCRIPTS"
REMOTE_ENV_FOLDER="$REMOTE_BASE_FOLDER/$FOLDER_NAME_ENV"
REMOTE_ETC_FOLDER="$REMOTE_BASE_FOLDER/$FOLDER_NAME_ETC"

declare -a OPTIONS=()
while getopts r?b?c?f?s?i?v?p?h?e opt; do
    case $opt in
    h)
        printHelpMenu
        exit 0
        ;;
    r)
        RESTART=1
        OPTIONS+=("auto-restart")
        ;;
    b)
        BUILD_FROM_SOURCE=1
        OPTIONS+=("build-from-source")
        ;;
    c)
        BUILD_WITHOUT_CACHE=1
        OPTIONS+=("no-cache")
        ;;
    p)
        PULL_LATEST_IMAGE=1
        OPTIONS+=("pull-latest-image")
        ;;
    f)
        SKIP_UPLOAD=1
        OPTIONS+=("no-package-files-upload")
        ;;
    v)
        DELETE_VOLUMES=1
        OPTIONS+=("delete-volumes")
        ;;
    s)
        SCRIPTS=1
        ;;
    i)
        INITIALIZE=1
        ;;
    e)
        UPLOAD_ETC=1
        ;;
    esac
done

if [ $INITIALIZE ]; then
    initialize
fi

if [ $SCRIPTS ]; then
    while true; do
        read -p "Do you wish to copy script files to $REMOTE_HOST? [y/n] " selection
        case $selection in
        [y]*)
            createScriptsFolder
            uploadScripts
            echo "Done!"
            exit 0
            ;;
        [n]*)
            exit 1
            ;;
        *) echo "Please answer y or n." ;;
        esac
    done
fi

if [ $UPLOAD_ETC ]; then
    while true; do
        read -p "Do you wish to upload etc folder to $REMOTE_HOST? [y/n] " selection
        case $selection in
        [y]*)
            createEtcFolder
            uploadEtcFolder
            echo "Done!"
            exit 0
            ;;
        [n]*)
            exit 1
            ;;
        *) echo "Please answer y or n." ;;
        esac
    done
fi

shift $((OPTIND - 1))
[ "${1:-}" = "--" ] && shift

loadPackageFromArgs $1
if [ "$?" -ne 0 ]; then
    echo ""
    echo "usage: deploy.sh [-rbfsivphe] package, use -h for help"
    echo ""
    exit 1
fi

echo ""
echo -n "Deploy Tool "
if [ ${#OPTIONS[@]} -gt 0 ]; then
    echo -n "("
    for i in "${!OPTIONS[@]}"; do
        if [ $i -gt 0 ]; then
            echo -n "; "
        fi
        echo -n "${OPTIONS[$i]}"
    done
    echo -ne ")\n"
else
    echo -ne "\n"
fi

echo "-----------------------------------"
echo "NAME:         $NAME"
echo "DESCRIPTION   $DESCRIPTION"
echo ""
echo -n "FILES         "
for index in "${!PACKAGE_FILES[@]}"; do
    if [[ $index == 0 ]]; then
        echo "${PACKAGE_FILES[$index]}"
    else
        echo "              ${PACKAGE_FILES[$index]}"
    fi
done
echo "-----------------------------------"
echo ""

while true; do
    read -p "Do you wish to deploy $NAME to $REMOTE_HOST? [y/n] " selection
    case $selection in
    [y]*) break ;;
    [n]*) exit ;;
    *) echo "Please answer y or n." ;;
    esac
done

REMOTE_PACKAGE_FOLDER="$REMOTE_PACKAGES_FOLDER/$NAME"
if [ ! $RESTART ]; then
    while true; do
        read -p "Do you wish to execute the run script for '$NAME' afterwards? [y/n] " selection
        case $selection in
        [y]*)
            RESTART="true"
            break
            ;;
        [n]*) break ;;
        *) echo "Please answer y or n." ;;
        esac
    done
fi

# create folders if they do not exist yet
ssh $REMOTE $SSH_OPTS "mkdir -p $REMOTE_PACKAGES_FOLDER && mkdir -p $REMOTE_SCRIPTS_FOLDER"
if [ "$?" -ne 0 ]; then
    echo "Error: Could not create remote folders!"
    exit 1
fi

#updating scripts
uploadScripts

if [ ! $SKIP_UPLOAD ]; then
    uploadPackageFiles
    createEnvLink
else
    echo "Skipping package files upload.."
fi

if [ $RESTART ]; then
    executeRun
fi

echo "--------------------------------------------"
echo "Timestamp: $(date)"
echo "--------------------------------------------"
echo "Successfully finished '$NAME' deployment!"
echo "--------------------------------------------"
