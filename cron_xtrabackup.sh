#!/bin/bash

# SCRIPT: cron_xtrabackup.sh
# AUTHOR: Ben Chambers
# DATE: September 2024
# VERSION: 1.05
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

# Set variables:
defaults_file="/etc/mysql/.xtrabackup.cnf"
# backup_owner="root"
environment="$2"
day_of_week_for_full="$3"
target_dir_full="/data/backups/$1/full"
target_dir_inc="/data/backups/$1/incremental"
target_dir_binlog="/data/backups/$1/binlog"
target_dir_lsn="/data/backups/$1/"
todays_dir="${target_dir_full}/$(hostname)-$(date +%F)"
todays_dir_inc="${target_dir_inc}/$(hostname)-$(date +%F)"
db_server="$(hostname)"
DATETIME="$(date '+%F %T')"
logfile="/data/backups/logs/${db_server}_xtrabackup.log"
recent_lsn="/data/backups/$1/recent_lsn"
encrypt_file_loc="/data/.keyfile"
mysql_db="/var/lib/mysql"
cleaned_lsn_path="placeholder"
day=$(date +%A)
retention_period="28"
#teams_channel="https://gwncsp.webhook.office.com/webhookb2/b1ddda3d-19cf-4585-92f4-5787c6098eaa@2f0e80a6-80a9-4c92-8401-b2711c15efdc/IncomingWebhook/4c26fb4f7e5849248ac948f824594f7b/6d1535ef-be9f-4aa2-89a6-b9b22e6148e2"
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
    curl -H "Content-Type: application/json" -d "{\"text\": \"$message\"}" $teams_channel
}


if 
[[ -z $1 ]]; then
        echo "$db_server - $(date '+%F %T'): Backup folder to place within target directory not passed as a command. Please invoke this after this script. E.g bash <script> <directory> " | tee -a "$logfile" 
else
        
if [ "$day" == "$day_of_week_for_full" ]; then
    #completes full backup, clears incrementals
        if
        [[ -e "$todays_dir" ]]; then
        #directory already exists, abort and error
        OUTPUT=$(echo "$db_server - $(date '+%F %T'): Full backup already exists for this day. Please check $todays_dir" | tee -a "$logfile")
        BACKUP_TYPE="Full"
        BACKUP_LOCATION="$todays_dir"
        BACKUP_SIZE="$(du -sh "$todays_dir" | cut -f1)"
        teams_notification
        exit 1

        else
        #carry on as normal
                if
                    #encryption file is present, do
                    [ -f "$encrypt_file_loc" ];then
                    #list of xtrabackup arguments
                    xtrabackup_args=(
                    "--defaults-file=${defaults_file}"
                    "--backup"
                    "--target-dir=${todays_dir}"
                    "--compress"
                    "--encrypt=AES256"
                    "--encrypt-key-file=${encrypt_file_loc}"
                    "--galera-info"
                    "--parallel=4"
                    "--compress-threads=4"
                    "--encrypt-threads=1"
                    "--open-files-limit=5096"
                    "--rsync"

                    )

                    echo "$db_server - $(date '+%F %T'): Encryption file found, commencing backup" >> "$logfile"
                    mkdir -p "$todays_dir"
                    xtrabackup "${xtrabackup_args[@]}" >> "$logfile"
                    
                    #echo "xtrabackup ${xtrabackup_args[@]}"
                    echo "$db_server - $(date '+%F %T'): Backing up .pem files and grastate.dat" >> "$logfile"
                    rsync -avrP "$mysql_db"/*.pem "$todays_dir"
                    rsync -avrP "$mysql_db"/grastate.dat "$todays_dir"
                    echo "$db_server - $(date '+%F %T'): .pem files and grastate.dat have been backed up. Full backup should be in $todays_dir." | tee -a "$logfile" 
                    #removes lost+found directory if present. This is due to it interfering with the restore.
                    rm -rf "$todays_dir"/lost+found

                    #puts the to_lsn into file so the incremental backup has it's starting point when script is run again
                    grep -oP '(?<=to_lsn\s=\s)\d+' "$todays_dir"/xtrabackup_checkpoints  | tee  "$recent_lsn"
                    if
                        #2 stage check to see first if xtrabackup_checkpoints exists, second if it contains the to_lsn field indicative of a successfull backup.
                        [[ -f "$todays_dir/xtrabackup_checkpoints" ]];then

                        checkpoints_lsn=$(<"/$todays_dir/xtrabackup_checkpoints")
                        # Extract the number after 'to_lsn = ' from content1
                        lsn_value=$(grep -oP '(?<=to_lsn\s=\s)\d+' <<< "$checkpoints_lsn")
                        recent_lsn_value=$(grep -oP '\d+' "$recent_lsn")
                        echo "lsn_value is $lsn_value"
                        echo "recent_lsn_value is $recent_lsn_value"
                        #recent_lsn is what we are comparing to
                        if
                        #to_lsn present and matching recent_lsn indicating successful backup. Incrementals now can be cleared. Clear any files or directories from full older than 28 days
                        [[ "$lsn_value" == "$recent_lsn_value" ]];then
                        echo "$db_server - $(date '+%F %T'): to_lsn in 'xtrabackup_checkpoints' is $lsn_value. This matches most recent LSN in'recent_lsn' which is $recent_lsn_value. Backup successful, proceeding to remove previous weeks incremental backups." | tee -a "$logfile" 
                        # Store backup info for notification
                        BACKUP_SUCCESS="1"
                        BACKUP_TYPE="Full"
                        BACKUP_LOCATION="$todays_dir"
                        BACKUP_SIZE="$(du -sh "$todays_dir" | cut -f1)"


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


                        

                        else
                        #what to do if to_lsn isn't present
                        OUTPUT=$(echo "$db_server - $(date '+%F %T'): to_lsn in 'xtrabackup_checkpoints'($lsn_value) either doesn't exist or differs from the value stored in 'recent_lsn' ($recent_lsn_value) Review the backup which should be in $todays_dir" | tee -a "$logfile" )
                        BACKUP_TYPE="Full"
                        BACKUP_LOCATION="$todays_dir"
                        BACKUP_SIZE="$(du -sh "$todays_dir" | cut -f1)"
                        teams_notification
                        exit 1
                        
                        fi

                    else
                        #what to do if xtrabackup_checkpoints doesn't exist, indicating failure
                        OUTPUT=$(echo "$db_server - $(date '+%F %T'): Xtrabackup_checkpoints isn't where it's expected to be. Please review backup" | tee -a "$logfile" )
                        BACKUP_TYPE="Full"
                        BACKUP_LOCATION="$todays_dir"
                        BACKUP_SIZE="$(du -sh "$todays_dir" | cut -f1)"
                        teams_notification
                        exit 1
                        
                    fi
                    
                    
                    
                else
                    #encryption file is not present, abort and note error in log
                    OUTPUT=$(echo "$db_server - $(date '+%F %T'): Encryption file not found in $encrypt_file_loc. Aborting backup and logging in $logfile." | tee -a "$logfile" )
                    BACKUP_TYPE="Full"
                    BACKUP_LOCATION="$todays_dir"
                    BACKUP_SIZE="$(du -sh "$todays_dir" | cut -f1)"
                    teams_notification
                    exit 1
                    
                fi
        fi
        
else #day is not saturday, commencing incremental. 

    if #recent lsn directory is present, go to the next stage.
    [[ -e "$recent_lsn" ]];then 
       #completes incremental backup
            if
            [[ -e "$todays_dir_inc" ]]; then
            #directory already exists, abort and error
            OUTPUT=$(echo "$db_server - $(date '+%F %T'): Incremental backup already exists for this day. Please check $todays_dir_inc" | tee -a "$logfile" )
            BACKUP_TYPE="Incremental"
            BACKUP_LOCATION="$todays_dir"
            BACKUP_SIZE="$(du -sh "$todays_dir" | cut -f1)"
            teams_notification
            exit 1

            else
                    if
                    #Prior to backup, below checks the value stored in the variable $recent_lsn. This value is the most recent 'to_lsn' value taken from a backup.
                    #It then looks within the full /data/backups directory for this value, which informs the correct backup to use as the base directory for the incremental.
                    #This will either be the full backup or the most recent incremental backup.

                    #incremental backup, needs to take input of to_lsn
                    #basedir directory will be informed by location of last recorded "to_lsn"
                    #encryption file is present, do
                    [ -f "$encrypt_file_loc" ];then
                    # Extract dynamic last_lsn value from log
                    dynamic_lsn=$(tail -n 1 "$recent_lsn" | grep -oP '\d+')
                    echo "$db_server - $(date '+%F %T'): Dynamic LSN = $dynamic_lsn" | tee -a "$logfile"

                    # searching for identified lsn within log files of backup folder to use as an input
                    lsn_path=$(sudo grep -Rnwl --exclude="recent_lsn" "$target_dir_lsn" -e "to_lsn = $dynamic_lsn")
                    echo "$db_server - $(date '+%F %T'): LSN Path = $lsn_path" | tee -a "$logfile"

                    # removes xtrabackup_checkpoints so filepath leads to backup.
                    cleaned_lsn_path=$(echo "$lsn_path" | sed 's/\/\xtrabackup_checkpoints//g')
                    echo "The base directory will be $cleaned_lsn_path"
                    
                    #list of xtrabackup arguments for incrementals.
                    xtrabackup_args_inc=(
                    "--defaults-file=${defaults_file}"
                    "--backup"
                    "--target-dir=${todays_dir_inc}"
                    "--incremental-basedir=${cleaned_lsn_path}"
                    "--encrypt=AES256"
                    "--encrypt-key-file=${encrypt_file_loc}"
                    "--galera-info"
                    "--parallel=4"
                    "--compress"
                    "--compress-threads=4"
                    "--encrypt-threads=1"
                    "--open-files-limit=5096"
                    "--rsync"
                )
                    #Incremental backup
                    echo "$db_server - $(date '+%F %T'): Encryption file found, commencing backup" | tee -a "$logfile"
                    mkdir -p "$todays_dir_inc"
                    xtrabackup "${xtrabackup_args_inc[@]}" >> "$logfile"
                    
                    #echo "xtrabackup ${xtrabackup_args_inc[@]}"
                    echo "$db_server - $(date '+%F %T'): Incremental backup completed." | tee -a "$logfile"
                    #puts the to_lsn into logfile so the incremental backup has it's starting point
                    grep "to_lsn = " "$todays_dir_inc"/xtrabackup_checkpoints  | tee "$recent_lsn"
                    if
                                #2 stage check to see first if xtrabackup_checkpoints exists, second if it contains the to_lsn field indicative of a successfull backup.
                                [[ -f "$todays_dir_inc/xtrabackup_checkpoints" ]];then

                                checkpoints_lsn=$(<"/$todays_dir_inc/xtrabackup_checkpoints")
                                # Extract the number after 'to_lsn = ' from checkpoints_lsn
                                lsn_value=$(grep -oP '(?<=to_lsn\s=\s)\d+' <<< "$checkpoints_lsn")
                                recent_lsn_value=$(grep -oP '\d+' "$recent_lsn")
                                echo "lsn_value is $lsn_value"
                                echo "recent_lsn_value is $recent_lsn_value"
                                #recent_lsn is what we are comparing to
                                if
                                #to_lsn present and matching recent_lsn indicating successful backup
                                [[ "$lsn_value" == "$recent_lsn_value" ]];then
                                echo "$db_server - $(date '+%F %T'): to_lsn in 'xtrabackup_checkpoints' is $lsn_value. This matches most recent LSN in'recent_lsn' which is $recent_lsn_value. Backup successful." | tee -a "$logfile" 
                                BACKUP_SUCCESS="1"
                                BACKUP_TYPE="Incremental"
                                BACKUP_LOCATION="$todays_dir_inc"
                                BACKUP_SIZE="$(du -sh "$todays_dir_inc" | cut -f1)"
                                #removes lost+found directory if present. This is due to it interfering with the restore.
                                rm -rf "$todays_dir_inc"/lost+found
                            

                                else
                                #what to do if to_lsn isn't present
                                OUTPUT=$(echo "$db_server - $(date '+%F %T'): to_lsn in 'xtrabackup_checkpoints'($lsn_value) either doesn't exist or differs from the value stored in 'recent_lsn' ($recent_lsn_value) Review the backup which should be in $todays_dir" | tee -a "$logfile" )
                                BACKUP_TYPE="Incremental"
                                BACKUP_LOCATION="$todays_dir"
                                BACKUP_SIZE="$(du -sh "$todays_dir" | cut -f1)"
                                teams_notification
                                exit 1
                                
                                fi

                    else
                        #what to do if xtrabackup_checkpoints doesn't exist, indicating failure
                        OUTPUT=$(echo "$db_server - $(date '+%F %T'): Xtrabackup_checkpoints isn't where it's expected to be. Please review backup" | tee -a "$logfile" )
                        BACKUP_TYPE="Incremental"
                        BACKUP_LOCATION="$todays_dir"
                        BACKUP_SIZE="$(du -sh "$todays_dir" | cut -f1)"
                        teams_notification
                        exit 1
                    fi

                    
                    else
                        #encryption file is not present, abort and note error in log
                        OUTPUT=$(echo "$db_server - $(date '+%F %T'): Encryption file not found in $encrypt_file_loc. Aborting backup and logging in $logfile." | tee -a "$logfile" )
                        BACKUP_TYPE="Incremental"
                        BACKUP_LOCATION="$todays_dir"
                        BACKUP_SIZE="$(du -sh "$todays_dir" | cut -f1)"
                        teams_notification
                        exit 1
                        
                    fi
            fi
    else #error, citing that recent_lsn file is either empty or not present
        OUTPUT=$(echo "$db_server - $(date '+%F %T'): File containing most recent lsn not found. Please review log for last full backup." | tee -a "$logfile" )
        BACKUP_TYPE="Incremental"
        BACKUP_LOCATION="$todays_dir"
        BACKUP_SIZE="$(du -sh "$todays_dir" | cut -f1)"
        teams_notification
        exit 1
        
    fi


 
    

fi


fi
teams_notification
exit 0
