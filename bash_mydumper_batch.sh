#!/bin/bash

#Instructions: Input the priority list you wish to migrate the domains of.

SET_GROUP="$1"

if [[ "$SET_GROUP" == '1' ]];then
# Domain list 1: L1 DB's
    sudo bash bash_mydumper_only.sh 10.200.10.190 6
    sudo bash bash_mydumper_only.sh 10.200.10.191 6
    sudo bash bash_mydumper_only.sh 10.200.10.195 6
    sudo bash bash_mydumper_only.sh 10.200.10.196 6
    sudo bash bash_mydumper_only.sh 46.175.48.29 6
    sudo bash bash_mydumper_only.sh 46.175.48.55 6
    sudo bash bash_mydumper_only.sh 46.175.48.101 6
    sudo bash bash_mydumper_only.sh 46.175.48.124 6
    sudo bash bash_mydumper_only.sh 46.175.48.126 6
    sudo bash bash_mydumper_only.sh 46.175.48.173 6
fi

if [[ "$SET_GROUP" == '2' ]];then
# Domain list 2: L2 DB's

    sudo bash bash_mydumper_only.sh 10.100.10.190 6
    sudo bash bash_mydumper_only.sh 10.100.10.191 6
    sudo bash bash_mydumper_only.sh 10.100.10.195 6
    sudo bash bash_mydumper_only.sh 10.100.10.196 6
    sudo bash bash_mydumper_only.sh 77.86.34.29 6
    sudo bash bash_mydumper_only.sh 77.86.34.55 6
    sudo bash bash_mydumper_only.sh 77.86.34.101 6
    sudo bash bash_mydumper_only.sh 77.86.34.124 6
    sudo bash bash_mydumper_only.sh 77.86.34.126 6
    sudo bash bash_mydumper_only.sh 77.86.34.173 6
fi

exit 0