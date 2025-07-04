#!/bin/bash

# SCRIPT: cron_mysqldump.sh
# AUTHOR: Ben Chambers
# DATE: October 2024
# VERSION: 1.00
# PLATFORM: Linux
# PURPOSE: This is a simple script which performs a MySQL Dump at the required time, it then compresses the backup using gzip and encrypts using openssl.
# It also notifies the DBA Backup Notification teams channel to enable adequate monitoring.

# High level steps.
# 1: Take mysqldump
# 2: Encrypt mysqldump
# 3: Post notification to teams channel.

# Set variables:
#$1 = name of backup dir

# Decrypting and decompressing backups:
# openssl enc -d -aes-256-cbc -in <encrypted file> -out <filename after decryption> -pass pass:<password that was set> -pbkdf2 -iter 100000
# gunzip <decrypted .gz file>

# Testing:
# bash -x cron_mysqldump.sh dg-enf-sysadmin "Enfield System Admin"
defaults_file="/root/.my.cnf"
environment="$2"
target_dir_full="/data/backups/$1/logical_full"
todays_dump="${target_dir_full}/$(hostname)-$(date +%F).sql"
db_server="$(hostname)"
DATETIME="$(date '+%F %T')"
logfile="/data/${db_server}_mysqldump.log"
retention_period="14"
teams_channel="https://gwncsp.webhook.office.com/webhookb2/b1ddda3d-19cf-4585-92f4-5787c6098eaa@2f0e80a6-80a9-4c92-8401-b2711c15efdc/IncomingWebhook/4c26fb4f7e5849248ac948f824594f7b/6d1535ef-be9f-4aa2-89a6-b9b22e6148e2/V2DJbWgxn1StHRA3e6Qyarkv4rzuCLdW9cxx8qPQob8Kg1"


teams_notification(){
#Date / Time of Backup: Set in backup
#Backup Type: Set in backup
#Backup Location: Set in backup
#Backup Size: Set in backup
local available_space=$(df -h --output=avail /data | tail -n 1)
local DATETIME="$(date '+%F %T')"
if [[ $BACKUP_SUCCESS == "1" ]];then
    message=$(echo -e "**Environment**: $environment \n\n -----------------  \n\n **Backup Successful:** \n\n **Date / Time of Backup:** $DATETIME \n\n **Backup Type:** $BACKUP_TYPE \n\n **Backup Location:** $BACKUP_LOCATION \n\n **Backup Size:** $BACKUP_SIZE \n\n **Remaining Space On Data Dir:** $available_space")
else
    message=$(echo -e "**Environment**: $environment \n\n -----------------  \n\n **Backup Failed:** \n\n **Error message:** $OUTPUT \n\n **Date / Time of Backup:** $DATETIME \n\n **Backup Type:** $BACKUP_TYPE \n\n **Backup Location:** $BACKUP_LOCATION \n\n **Backup Size:** $BACKUP_SIZE \n\n **Remaining Space On Data Dir:** $available_space")
 
fi
    curl -H "Content-Type: application/json" -d "{\"text\": \"$message\"}" "$teams_channel"
}

mysqldump_backup(){
    mysqldump_args=(
        "--defaults-file=${defaults_file}"
        "--all-databases"
        "--triggers"
        "--events"
        "--routines"
        "--single-transaction"
    )
echo "${mysqldump_args[@]}"
if mysqldump "${mysqldump_args[@]}" > "$todays_dump" 2>> "$logfile"; then
    #proceed to compression and encryption
    if gzip "$todays_dump" >> "$logfile";then
        #compression successful, encrypt using root password within default
        password=$(grep -Po "(?<=password=)(.*)" "$defaults_file")
        if openssl enc -aes-256-cbc -salt -in "$todays_dump".gz -out "$todays_dump".gz.enc -pass pass:"$password" -pbkdf2 -iter 100000; then
            #encryption successful
            rm "$todays_dump".gz
            #remove backups older than retention period
            find "$target_dir_full" -mtime +"$retention_period" -exec rm -rf {} \;
            echo "$db_server - $(date '+%F %T'): MySQL Dump, compression and encryption successful, proceeding to notify" | tee -a "$logfile"
            BACKUP_SUCCESS="1"
            BACKUP_TYPE="Full Logical"
            BACKUP_LOCATION="$todays_dump".gz.enc
            #this may need tweaking as for directories.
            BACKUP_SIZE="$(du -sh "$todays_dump".gz.enc | cut -f1)"
        else
            #encrytion failed, log and quit.
            OUTPUT=$(echo "$db_server - $(date '+%F %T'): MySQL Dump and compression successful, encryption failed. Please review $logfile" | tee -a "$logfile" )
            BACKUP_TYPE="Full Logical"
            BACKUP_LOCATION="$todays_dump".gz
            #this may need tweaking as for directories.
            BACKUP_SIZE="$(du -sh "$todays_dump".gz | cut -f1)"
            teams_notification
            exit 1
        fi
    else
        #compresion failed, note this to error log.
        OUTPUT=$(echo "$db_server - $(date '+%F %T'): MySQL Dump successful but compression failed. Please review $logfile" | tee -a "$logfile" )
        BACKUP_TYPE="Full Logical"
        BACKUP_LOCATION="$todays_dump"
        #this may need tweaking as for directories.
        BACKUP_SIZE="$(du -sh "$todays_dump" | cut -f1)"
        teams_notification
        exit 1
    fi
else 
    #Error and exit
    OUTPUT=$(echo "$db_server - $(date '+%F %T'): MySQL Dump Failed for this day. Please review $logfile" | tee -a "$logfile" )
    BACKUP_TYPE="Full Logical"
    BACKUP_LOCATION="$todays_dump"
    #this may need tweaking as for directories.
    BACKUP_SIZE="$(du -sh "$todays_dump" | cut -f1)"
    teams_notification
    exit 1
fi
}
mkdir -p "$target_dir_full"

if mysqldump_backup; then
    teams_notification
    exit 0 
else
    #Error and exit
    OUTPUT=$(echo "$db_server - $(date '+%F %T'): MySQL Dump unable to start. Please review $logfile" | tee -a "$logfile" )
    BACKUP_TYPE="Full Logical"
    BACKUP_LOCATION="$todays_dump"
    #this may need tweaking as for directories.
    BACKUP_SIZE="$(du -sh "$todays_dump" | cut -f1)"
    teams_notification
    exit 1
fi