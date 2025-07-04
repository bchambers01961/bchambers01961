#!/bin/bash

# SCRIPT: cron_xtrabackup.sh
# AUTHOR: Ben Chambers
# DATE: February 2025
# VERSION: 2.00
# PLATFORM: Linux
# PURPOSE: This script performs either a full or incremental backup depending on the day of the week. It also logs to a file which
# is used to inform which backup should act as the base directory.

# Below will add the bash scripts log to logrotate.
#sudo echo "
#/data/backups/mes_xtrabackup_log
#{
#        rotate 4
#        weekly
#        missingok
#        notifempty
#        compress
#        delaycompress
#}
#" | sudo tee /etc/logrotate.d/cron_xtrabackup

# Example call
# sudo bash /root/scripts/cron_xtrabackup.sh testing 'MES 2019: New Script Test' Friday

# Notes / changes:
# Seperated LSN from logfile as only the most recent value should be used.
# Backups taken and work as expected, now just need to set the behaviour based on the day of the week.
# If Saturday we will do a full backup, any other day will be incremental.
# Changed last lsn to to lsn as this is the stopping point of the backup
# Identified that whilst files older than retention period are removed, directories remained. Added something to address this
# 1.01: Added $1 value to pass different directories
# 1.02: Added segments to remove lost+found directory being erroneuously taken with backups
# 1.03: Added notifications to DB Alerting Teams channel. Also added environment to second variable to give greater detail.
# 1.04: Added cleanup for binlog folder upon completion of a full backup. Keeps most recent 3 days just in case. Also changed log directory to dedicated folder.
# 1.05: Added flag so day of week can be defined in cron job.
# 2.00: Rebuilt from ground up to implement lessons learned since original script.

# Set Global variables:
defaults_file="/etc/mysql/.xtrabackup.cnf"
# backup_owner="root"
environment="$2"
day_of_week_for_full="$3"
target_dir_name="$1"
target_dir_full="/data/backups/$1/full"
target_dir_inc="/data/backups/$1/incremental"
target_dir_binlog="/data/backups/$1/binlog"
target_dir_lsn="/data/backups/$1/"
todays_dir="${target_dir_full}/$(hostname)-$(date +%F)"
todays_dir_inc="${target_dir_inc}/$(hostname)-$(date +%F)"
certs_dir="$(grep -oP '(?<=ssl-key=).+\/' /etc/mysql/my.cnf)"
db_server="$(hostname)"
DATETIME="$(date '+%F %T')"
logfile="/data/backups/logs/${db_server}_xtrabackup.log"
recent_lsn="Placeholder"
encrypt_file_loc="/data/.keyfile"
mysql_db="/var/lib/mysql"
cleaned_lsn_path="placeholder"
day=$(date +%A)
retention_period="28"
#teams_channel="https://gwncsp.webhook.office.com/webhookb2/b1ddda3d-19cf-4585-92f4-5787c6098eaa@2f0e80a6-80a9-4c92-8401-b2711c15efdc/IncomingWebhook/4c26fb4f7e5849248ac948f824594f7b/6d1535ef-be9f-4aa2-89a6-b9b22e6148e2"
teams_channel="https://gwncsp.webhook.office.com/webhookb2/b1ddda3d-19cf-4585-92f4-5787c6098eaa@2f0e80a6-80a9-4c92-8401-b2711c15efdc/IncomingWebhook/4c26fb4f7e5849248ac948f824594f7b/6d1535ef-be9f-4aa2-89a6-b9b22e6148e2/V2DJbWgxn1StHRA3e6Qyarkv4rzuCLdW9cxx8qPQob8Kg1"
parallel_cores=$(lscpu | awk '/^CPU\(s\):/ {printf "%.0f\n", $2 * 0.50}');
compress_cores=$(lscpu | awk '/^CPU\(s\):/ {printf "%.0f\n", $2 * 0.25}');


# Xtrabackup Configs:
xtrabackup_args=(
                    "--defaults-file=${defaults_file}"
                    "--backup"
                    "--target-dir=${todays_dir}"
                    "--compress"
                    "--encrypt=AES256"
                    "--encrypt-key-file=${encrypt_file_loc}"
                    "--galera-info"
                    "--parallel=${parallel_cores}"
                    "--compress-threads=${compress_cores}"
                    "--encrypt-threads=1"
                    "--open-files-limit=5096"
                    "--rsync"

                    )
xtrabackup_args_inc=(
                    "--defaults-file=${defaults_file}"
                    "--backup"
                    "--target-dir=${todays_dir_inc}"
                    "--incremental-basedir=${recent_lsn_dir}"
                    "--encrypt=AES256"
                    "--encrypt-key-file=${encrypt_file_loc}"
                    "--galera-info"
                    "--parallel=${parallel_cores}"
                    "--compress"
                    "--compress-threads=${compress_cores}"
                    "--encrypt-threads=1"
                    "--open-files-limit=5096"
                    "--rsync"
                )



# Function breakdown:
# 0: Backup Cleanup
backup_binlog_cleanup(){
    #rm -rf "$target_dir_inc"/*
    shopt -s dotglob  # Enable globbing to include hidden files
    rm -rf "${target_dir_inc:?}/"*
    shopt -u dotglob  # Disable globbing to exclude hidden files

    echo "$db_server - $(date '+%F %T'): Previous week's incrementals successfully removed" | tee -a "$logfile"
    #removes any backups older than retention period which is set as a variable
    find "$target_dir_full" -mtime +"$retention_period" -exec rm -rf {} \;
    find "$target_dir_full" -empty -type d -delete 
    echo "$db_server - $(date '+%F %T'): Full backups older than $retention_period days removed" | tee -a "$logfile"

    # Clears binlog backups older than 3 days and removes any empty directories.
    find "$target_dir_binlog" -type f -mtime +3 -exec rm -f {} \;
    find "$target_dir_binlog" -type d -empty -delete
    echo "$db_server - $(date '+%F %T'): Binary log backups older than 3 days removed." | tee -a "$logfile"

}

# 1: Xtrabackup Full
xtrabackup_full(){

if [ -f "$encrypt_file_loc" ];then
    #encryption file is present, commence xtrabackup.
    echo "$db_server - $(date '+%F %T'): Encryption file found, commencing backup" | tee -a "$logfile"
    mkdir -p "$todays_dir"
    if xtrabackup "${xtrabackup_args[@]}" >> "$logfile";then
        # xtrabackup successful, copy grastate and certs
        echo "$db_server - $(date '+%F %T'): Backing up .pem files and grastate.dat" | tee -a "$logfile"
        if [[ -e "$mysql_db"/grastate.dat ]];then
            # grastate.dat present, indicating this is an xtradb cluster. Copy grastate.dat and certs.
            # what if certs aren't in /var/lib/mysql
            rsync -avrP "$certs_dir"*.pem "$todays_dir"
            rsync -avrP "$mysql_db"/grastate.dat "$todays_dir"
        else
            # grastate.dat not present, indicating this is a standalone server
            rsync -avrP "$certs_dir"*.pem "$todays_dir"
        fi
        echo "$db_server - $(date '+%F %T'): .pem files and grastate.dat have been backed up. Full backup should be in $todays_dir." | tee -a "$logfile" 
        #removes lost+found directory if present. This is due to it interfering with the restore.
        rm -rf "$todays_dir"/lost+found
        BACKUP_SUCCESS="1"
        BACKUP_TYPE="Full"
        BACKUP_LOCATION="$todays_dir"
        BACKUP_SIZE="$(du -sh "$todays_dir" | cut -f1)"
        
    else
    #echo "$db_server - $(date '+%F %T'): Xtrabackup has failed for $todays_dir. Please review logfile" | tee -a "$logfile"
    OUTPUT=$(echo "$db_server - $(date '+%F %T'): Xtrabackup has failed for $todays_dir. Please review logfile" | tee -a "$logfile")
    return 1
    fi

else
    #encryption file is not present, abort and note error in log
    OUTPUT=$(echo "$db_server - $(date '+%F %T'): Encryption file not found in $encrypt_file_loc. Aborting backup and logging in $logfile." | tee -a "$logfile" )
    BACKUP_TYPE="Full"
    BACKUP_LOCATION="$todays_dir"
    BACKUP_SIZE="$(du -sh "$todays_dir" | cut -f1)"
    teams_notification
    return 1
fi
}

# 2: LSN Seek
lsn_seek(){
# High level steps
# 1: Using the main directory (e.g central, av, p_reg) and change to it.
# 2: Find most recent full backup directory that isn't empty. Note the name of the server as different nodes will use different LSN's.
# 3: Using find, narrow down a list of the full and incremental backups.
# 4: Search through these and find the highest LSN. This is of the most recent full / increment. LSN's only over increase.
# 5: This LSN informs the basedir that the incremental will be based off.

cd "$target_dir_lsn" || return 1

# This works in a simpler way,
# 1: it finds all xtrabackup_checkpoints in the chosen directory.
# 2: It uses printf to display the creation time in datecode format, as well as the filepath.
# 3: It then sorts oldest - newest, using tail to pick and only keep whichever is newest.
# 4: It then uses cut to only keep everything after the space after the datecode - in this case only the filepath.
# find  /data/backups/$1/full /data/backups/$1/incremental/ -maxdepth 2 -type f -not -empty -name "xtrabackup_checkpoints" -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-
if lsn_dir=$(find  /data/backups/$target_dir_name/full /data/backups/$target_dir_name/incremental/ -maxdepth 2 -type f -not -empty -name "xtrabackup_checkpoints" -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-
); then
    recent_lsn=$(cat $lsn_dir | grep -oP '^to_lsn\s+\=\s+\d+$')
    recent_lsn_dir=$(dirname "$lsn_dir")


    #Debug
    #echo "$db_server - $(date '+%F %T'): $lsn_dir is the xtrabackup_checkpoints being used" | tee -a "$logfile"
    #echo "$db_server - $(date '+%F %T'): $recent_lsn is what xtrabackup will be looking for." | tee -a "$logfile"
    #echo "$db_server - $(date '+%F %T'): $recent_lsn_dir is the directory of the previous backup. This will be the incremental basedir." | tee -a "$logfile"
else
    OUTPUT=$(echo "$db_server - $(date '+%F %T'): Most recent lsn is unable to be located within $lsn_dir, exiting." | tee -a "$logfile")
    return 1
fi
}

# 3: Xtrabackup Incremental
xtrabackup_incremental(){
if [ -f "$encrypt_file_loc" ];then
    #encryption file is present, commence xtrabackup.
    echo "$db_server - $(date '+%F %T'): Encryption file found, commencing backup" | tee -a "$logfile"
    mkdir -p "$todays_dir_inc"
    # Debug
    echo "$db_server - $(date '+%F %T'): $recent_lsn_dir is what xtrabackup is looking for in incremental_basedir." | tee -a "$logfile"
    echo "${xtrabackup_args_inc[@]}" 
    if xtrabackup "${xtrabackup_args_inc[@]}" >> "$logfile";then
        # xtrabackup successful, copy grastate and certs
        echo "$db_server - $(date '+%F %T'): Incremental backup successful. " | tee -a "$logfile"
        rm -rf "$todays_dir_inc"/lost+found
        BACKUP_SUCCESS="1"
        BACKUP_TYPE="Incremental"
        BACKUP_LOCATION="$todays_dir_inc"
        BACKUP_SIZE="$(du -sh "$todays_dir_inc" | cut -f1)"
        
    else
    OUTPUT=$(echo "$db_server - $(date '+%F %T'): Xtrabackup has failed for $todays_dir_inc. Please review logfile" | tee -a "$logfile")
    return 1
    fi

else
    #encryption file is not present, abort and note error in log
    OUTPUT=$(echo "$db_server - $(date '+%F %T'): Encryption file not found in $encrypt_file_loc. Aborting backup and logging in $logfile." | tee -a "$logfile" )
    BACKUP_TYPE="Full"
    BACKUP_LOCATION="$todays_dir"
    BACKUP_SIZE="$(du -sh "$todays_dir" | cut -f1)"
    teams_notification
    return 1
fi
}

# 4: Teams notification

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
    curl -H "Content-Type: application/json" -d "{\"text\": \"$message\"}" $teams_channel
}

# Script body
# 1: Work out what day it is.
# 2: If incremental, run lsn_seek first to get correct directory for incremental. 
# 2b: If full, run binlog cleanup afterwards.
# 3: Run full or incremental based on the day.
# 4: Teams notification, indicating success.


if 
[[ -n $1 ]]; then
    echo "$db_server - $(date '+%F %T'): Backup folder to place within target directory is $target_dir_name. Proceeding with backup." | tee -a "$logfile"
    # This decides whether to do a full or incremental backup based on the day of the week
    if [ "$day" == "$day_of_week_for_full" ]; then
        echo "$db_server - $(date '+%F %T'): Day of the week is $day_of_week_for_full, proceeding with full backup." | tee -a "$logfile"
        xtrabackup_full
        backup_binlog_cleanup
    else
        echo "$db_server - $(date '+%F %T'): Day of the week is not $day_of_week_for_full, proceeding with incremental backup." | tee -a "$logfile"
        if lsn_seek;then
        # Re set xtrabackup array with up to date recent_lsn_dir
            xtrabackup_args_inc=(
                        "--defaults-file=${defaults_file}"
                        "--backup"
                        "--target-dir=${todays_dir_inc}"
                        "--incremental-basedir=${recent_lsn_dir}"
                        "--encrypt=AES256"
                        "--encrypt-key-file=${encrypt_file_loc}"
                        "--galera-info"
                        "--parallel=${parallel_cores}"
                        "--compress"
                        "--compress-threads=${compress_cores}"
                        "--encrypt-threads=1"
                        "--open-files-limit=5096"
                        "--rsync"
                    )
            xtrabackup_incremental
        else
            OUTPUT=$(echo "$db_server - $(date '+%F %T'): LSN Seek unable to find a previous backup, does one exist in $target_dir_lsn?" | tee -a "$logfile")
            exit 1
        fi
    fi

else
    echo "$db_server - $(date '+%F %T'): Backup folder to place within target directory not passed as a command. Please invoke this after this script. E.g bash <script> <directory> " | tee -a "$logfile" 
    exit 1
fi

# Send teams notification, indicating outcome.
teams_notification
exit 0
