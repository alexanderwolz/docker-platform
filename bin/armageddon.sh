#!/bin/bash
# Copyright (C) 2023 Alexander Wolz <mail@alexanderwolz.de>


echo ""
echo "!!!! ARMAGEDDON !!!!"
echo "--------------------"
echo "This script removes all Docker containers, images and volumes .."
echo "->    ON THIS LOCAL MACHINE ($(hostname))    <-"
echo "Consider taking backups before execution!"
echo ""

while true; do
    read -p "Do you wish to continue? [y/n] " selection
    case $selection in
    [y]*)

        while true; do
            read -p "Are you really, really sure? [y/n] " selection
            case $selection in
            [y]*)
                docker stop $(docker ps -aq)
                docker rm $(docker ps -aq)
                docker network prune -f
                docker rmi -f $(docker images --filter dangling=true -qa)
                docker volume rm $(docker volume ls --filter dangling=true -q)
                docker rmi -f $(docker images -qa)
                echo "Done!"
                exit 0
                ;;
            [n]*)
                exit 0
                ;;
            *) echo "Please answer y or n." ;;
            esac
        done
        ;;
    [n]*)
        exit 0
        ;;
    *) echo "Please answer y or n." ;;
    esac
done
