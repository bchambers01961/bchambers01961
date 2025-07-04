#!/bin/bash

# SCRIPT: bash_xtrabackup_restore.sh
# AUTHOR: Ben Chambers
# DATE: November 2024
# VERSION: 1.02
# PLATFORM: Linux
# PURPOSE: This script automates the process of testing the restore process on backed up DB's. Allowing DBA's to focus on verification steps

# High Level steps:
# 1: Clear data dir 
# 2: Work out which DB is full to restore and which are it's incrementals. (consider end of month) - done
# 3: With these factored in, copy each of them to the restore directory. - done 
# 4: Run Xtrabackup to decompress and decrypt restores.
# 5: Prepare restores
# 6: Copy restore into /var/lib/mysql
# 7: Change owner of DB to mysql
# 8: Start mysql service
# 9: If service starts, clear restore directory, if not log an error.
# 10: Post Success or Failure to DBA Backup Restore Channel.

# Test call
# sudo bash -x bash_xtrabackup_restore.sh p_reg "Restore for Replication"

# Notes / Changes:
# 1.01: Line 47 and 73 - changed how directories are listed to exclude empty ones.
# 1.02: Added --use-memory flag to prepare phase as this was taking too long.
# Global Variables:
mysql_db="/var/lib/mysql"
logfile="/data/$(hostname)_xtrabackup_restore.log"
mysql_defaults="/home/bchambers/.my.cnf"
encrypt_file_loc="/data/.keyfile"
backup_dir="/data/backups/$1"
restore_dir="/data/backups/$1/restore"
counter=0
environment="$2"
teams_channel="https://gwncsp.webhook.office.com/webhookb2/b1ddda3d-19cf-4585-92f4-5787c6098eaa@2f0e80a6-80a9-4c92-8401-b2711c15efdc/IncomingWebhook/5570eb313fc04dd29d5017218ac7ab61/6d1535ef-be9f-4aa2-89a6-b9b22e6148e2/V2wejWUqc7QEgkFsiK_F29pddc9l7WgTsVCiLHnQYb_No1"

# Functions:
DB_identification(){
    # identify full directory
    #change to directory where full backups stored.
    cd "$backup_dir"/full || exit 1

    # list dirs
    # dirs=$(ls -d */)
    # list dirs using find to filter out empty dirs from failed backups (1.01)
    dirs=$(find -maxdepth 1 -type d -not -empty)

    # Extract dates and sort
    sorted_dirs=$(
        for dir in $dirs; do
            # Extract the date part (YYYY/MM/DD)
            date_part=$(echo "$dir" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
            # Remove trailing slash
            dir=$(echo "$dir" | sed 's:/*$::')
            echo "$date_part $dir"
        done | sort | awk '{print $2}'
        )

    # Confirm most recent full directory
    full_dir="$(echo "$sorted_dirs" | tail -1)"
    echo "$full_dir"


    
    #identify incremental directories
    inc_dirs=""
    cd "$backup_dir"/incremental || exit 1

    #list dirs
    #dirs=$(ls -d */)
    # list dirs using find to filter out empty dirs from failed backups (1.01)
    dirs=$(find -maxdepth 1 -type d -not -empty)

    # Extract dates and sort
    sorted_dirs=$(
        for dir in $dirs; do
            # Extract the date part (YYYY/MM/DD)
            date_part=$(echo "$dir" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
            # Remove trailing slash
            dir=$(echo "$dir" | sed 's:/*$::')
            echo "$date_part $dir"
        done | sort | awk '{print $2}'
    )

    # Confirm list of incremental dirs
    inc_dirs="$(echo "$sorted_dirs" )"
    echo "$inc_dirs"
}

DB_copy_to_restore(){
    # Copy identified backups to restore directory
    # Clear restore dir
    rm -rf "${restore_dir:?}"/*
    
    # Full
    cd "$backup_dir"/full || exit 1
    echo "$full_dir is what rsync sees for source"
    echo "$restore_dir is what rsync sees for destination"
    if rsync -avrP "$full_dir" "$restore_dir"; then
        echo "$(date '+%F %T'): Successfully copied $full_dir to $restore_dir" | tee -a "$logfile"
    else
        OUTPUT=$(echo "$(date '+%F %T'): Failed to copy $full_dir to $restore_dir" | tee -a "$logfile")
        exit 1
    fi

    # Incrementals
    cd "$backup_dir"/incremental || exit 1
    for dir in $inc_dirs; do
        if rsync -avrP "$dir" "$restore_dir/"; then
            echo "$(date '+%F %T'): Successfully copied $dir to $restore_dir/" | tee -a "$logfile"
        else
            OUTPUT=$(echo "$(date '+%F %T'): Failed to copy $dir to $restore_dir" | tee -a "$logfile")
            exit 1
        fi
        
    done

    # Generate list of restore dirs
    cd "$restore_dir" || exit 1
     #list dirs
    dirs=$(ls -d */)

    # Extract dates and sort
    sorted_dirs=$(
        for dir in $dirs; do
            # Extract the date part (YYYY/MM/DD)
            date_part=$(echo "$dir" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
            echo "$date_part $dir"
        done | sort | awk '{print $2}'
    )

    # Confirm list of restore dirs
    restore_dir_list="$(echo "$sorted_dirs" )"
    echo "$restore_dir_list"
}

DB_decrypt(){
# take 75% of cores and apply to parralel setting.
cpu_cores=$(lscpu | awk '/^CPU\(s\):/ {printf "%.0f\n", $2 * 0.75}');

#decryption arguments
    # reference only, can remove once tested: sudo xtrabackup --decompress --remove-original --decrypt=AES256 --encrypt-key-file=/data/.keyfile --parallel=8 --target-dir=mes-l2-db-sreg-01-2024-10-05
local xtrabackup_args_decrypt=(
                    "--decompress"
                    "--decrypt=AES256"
                    "--encrypt-key-file=${encrypt_file_loc}"
                    "--remove-original"
                    "--parallel=${cpu_cores}"
                    )

# cd to directory restore is being done in
cd "$restore_dir" || exit 1
# decrypt and decompress each directory
for dir in $restore_dir_list; do
    #this
    if xtrabackup "${xtrabackup_args_decrypt[@]}" --target-dir="$dir"; then
        echo "$(date '+%F %T'): Decryption succeeded for directory: $dir" | tee -a "$logfile"
        counter=$((counter+1))
    else
        OUTPUT=$(echo "$(date '+%F %T'): Decryption failed for directory: $dir" | tee -a "$logfile")
        exit 1
    fi
done
}

DB_prepare(){
# Get 75% of total memory for Prepare. Will append G to the end for Gigabytes.
memory=$(awk '/MemTotal/ {printf "%.0fG", $2/1048576 * 0.75}' /proc/meminfo);
--use-memory=$memory

# Stop mysql service ready for prepare
systemctl stop mysql

# Move to directory restores are stored.
cd "$restore_dir" || exit 1
# Counter to show how many directories there are to be prepared.
echo "$counter"
# Learn earliest dir in restore directory as this will be the full restore. The full and inc are moved at the previous stage so no margin for error here.
full_dir_restore="$(ls | sort -n | head -1)"
last_dir_restore="$(ls | sort -n | tail -1)"
inbetween_dir_restores=$(ls | sort -n | sed -n "/$full_dir_restore/,/$last_dir_restore/p" | sed '1d;$d')
echo "Full dir: $full_dir_restore"
echo "Last dir: $last_dir_restore"
echo "Inbetween dirs: $inbetween_dir_restores"
if [[ "$counter" -eq 1 ]]; then
    # If there is 1 directory, just a full backup being restored.
    echo "$(date '+%F %T'): Preparing $full_dir_restore" as the full backup. | tee -a "$logfile"
    if sudo xtrabackup --prepare --use-memory="$memory" --target-dir="$full_dir_restore"; then
        echo "$(date '+%F %T'): Prepare succeeded for directory: $full_dir_restore" | tee -a "$logfile"
    else
        OUTPUT=$(echo "$(date '+%F %T'): Prepare failed for directory: $full_dir_restore" | tee -a "$logfile")
        exit 1
    fi
    #echo "only 1 dir"
elif [[ "$counter" -eq 2 ]]; then
    # If there is 2 directories, there is a full backup as well as an incremental.
    echo "$(date '+%F %T'): Preparing $full_dir_restore" as the full backup. | tee -a "$logfile"
    if sudo xtrabackup --prepare --apply-log-only --use-memory="$memory" --target-dir="$full_dir_restore"; then 
        echo "$(date '+%F %T'): Prepare succeeded for directory: $full_dir_restore" | tee -a "$logfile"
        # First prepare successful, proceed to prepare increment
        echo "$(date '+%F %T'): Preparing last incremental backup $last_dir_restore against full backup $full_dir_restore" | tee -a "$logfile"
        if sudo xtrabackup --prepare --use-memory="$memory" --target-dir="$full_dir_restore" --incremental-dir="$last_dir_restore"; then
            echo "$(date '+%F %T'): Prepare succeeded for directory: $last_dir_restore" | tee -a "$logfile"
        else
            OUTPUT=$(echo "$(date '+%F %T'): Prepare failed for directory: $last_dir_restore" | tee -a "$logfile")
            exit 1
        fi
    else
        OUTPUT=$(echo "$(date '+%F %T'): Prepare failed for directory: $full_dir_restore" | tee -a "$logfile")
        exit 1
    fi
    #echo "exactly 2 dirs"
elif [[ "$counter" -gt 2 ]]; then
    # If there are more than 2 directories, restore full, incs as normal up until the last one.
    echo "$(date '+%F %T'): Preparing $full_dir_restore" as the full backup. | tee -a "$logfile"
    if sudo xtrabackup --prepare --apply-log-only --use-memory="$memory" --target-dir="$full_dir_restore"; then
        # For loop which handles incrementals inbetween first and last
        for dir in $inbetween_dir_restores; do
            echo "$(date '+%F %T'): Preparing incremental backup $dir against full backup $full_dir_restore" | tee -a "$logfile"
            if xtrabackup --prepare --apply-log-only --use-memory="$memory" --target-dir="$full_dir_restore" --incremental-dir="$dir"; then
                echo "$(date '+%F %T'): Prepare succeeded for directory: $dir" | tee -a "$logfile"
            else
                OUTPUT=$(echo "$(date '+%F %T'): Prepare failed for directory: $dir" | tee -a "$logfile")
                exit 1
            fi
        done
    else
        OUTPUT=$(echo "$(date '+%F %T'): Prepare failed for directory: $full_dir_restore" | tee -a "$logfile")
        exit 1
    fi
    # Proceed to restore last backup, finalising preparation phase.
    echo "$(date '+%F %T'): Preparing last incremental backup $last_dir_restore against full backup $full_dir_restore" | tee -a "$logfile"
    if sudo xtrabackup --prepare --use-memory="$memory" --target-dir="$full_dir_restore" --incremental-dir="$last_dir_restore"; then
        echo "$(date '+%F %T'): Prepare succeeded for directory: $last_dir_restore, $full_dir_restore can now be restored to datadir" | tee -a "$logfile"
    else 
        OUTPUT=$(echo "$(date '+%F %T'): Prepare failed for directory: $last_dir_restore" | tee -a "$logfile")
        exit 0
    fi
fi
}

DB_restore_to_datadir(){
if rm -rf "$mysql_db";then
    # Clear mysql directory
    echo "$(date '+%F %T'): MySQL Data directory $mysql_db cleared, proceeding to create new directory for restore" | tee -a "$logfile"
    mkdir "$mysql_db"
    # Will need something here to make lost and found once additional storage added.
    echo "$(date '+%F %T'): $mysql_db recreated, moving files back." | tee -a "$logfile"   
else
    echo "$(date '+%F %T'): MySQL Data directory $mysql_db unable to be cleared, restore will be attempted but may error if files still present." | tee -a "$logfile"
    
fi

# Move to directory restores are stored. Should already be here but just in case.
    cd "$restore_dir" || exit 1
    if sudo xtrabackup --copy-back --target-dir="$full_dir_restore" --parallel="${cpu_cores}";then
        echo "$(date '+%F %T'): Xtrabackup $full_dir_restore successfully restored to $mysql_db. Changing ownership and starting mysql" | tee -a "$logfile"
        chown -R mysql:mysql "$mysql_db"
        if systemctl start mysql; then
            echo "$(date '+%F %T'): MySQL Service successfully started. Restore successful, proceeding to remove restore files and exiting"  | tee -a "$logfile"
            rm -rf "${restore_dir:?}"/*
            cd "$mysql_db" || exit 1
            #recreate lost+found
            mklost+found
            RESTORE_SUCCESS="1"
        else
            OUTPUT=$(echo "$(date '+%F %T'): MySQL Service failed to start, exiting script"  | tee -a "$logfile")
            
            exit 1
        fi
    else
        OUTPUT=$(echo "$(date '+%F %T'): Xtrabackup $full_dir_restore failed to restore to $mysql_db. Exiting script." | tee -a "$logfile")
        exit 1
    fi
}

teams_notification(){
#Date / Time of Backup: Set in backup
#Backup Type: Set in backup
#Backup Location: Set in backup
#Backup Size: Set in backup
local available_space=$(df -h --output=avail /data | tail -n 1)
local DATETIME="$(date '+%F %T')"
if [[ $RESTORE_SUCCESS == "1" ]];then
    message=$(echo -e "**Environment**: $environment \n\n -----------------  \n\n **Restore Successful:** \n\n **Date / Time of Restore:** $DATETIME \n\n **Restored To:** $(hostname) \n\n **Data Directory:** $mysql_db \n\n **Dataset Size:** "$DB_SIZE"GB \n\n **Time Taken:** $TOTAL_TIME")
else
    message=$(echo -e "**Environment**: $environment \n\n -----------------  \n\n **Restore Failed:** \n\n **Error message:** $OUTPUT \n\n **Date / Time of Restore:** $DATETIME \n\n **Restored To:** $(hostname) \n\n **Data Directory:** $mysql_db \n\n")
 
fi
    curl -H "Content-Type: application/json" -d "{\"text\": \"$message\"}" $teams_channel

    OUTPUT=$()
}
# Log the start time
STARTTIME="$(date '+%T')"

DB_identification 
DB_copy_to_restore
DB_decrypt
DB_prepare
DB_restore_to_datadir

# Log the end time and total time taken
ENDTIME="$(date '+%T')"

# Convert STARTTIME and ENDTIME to seconds since the epoch
START_SECONDS=$(date -d "$STARTTIME" +%s)
END_SECONDS=$(date -d "$ENDTIME" +%s)

# Calculate the total migration time in seconds
TOTAL_SECONDS=$((END_SECONDS - START_SECONDS))

# Convert total seconds to hours, minutes, and seconds
TOTAL_TIME=$(printf '%02d:%02d:%02d' $((TOTAL_SECONDS/3600)) $((TOTAL_SECONDS%3600/60)) $((TOTAL_SECONDS%60)))

# Grab size of dataset for teams notification.
QUERY="select round(sum(datalength)+sum(indexlength),2) AS dataset_size from
( select data_length/1024/1024/1024 datalength, index_length/1024/1024/1024 indexlength from information_schema.tables
where table_schema not in ('information_schema', 'performance_schema', 'sys', 'mysql') ) dd;"

DB_SIZE="$(mysql --defaults-file="$mysql_defaults" --skip-column-names -e "$QUERY")"
teams_notification
exit 0

bash /root/scripts/bash_xtrabackup_restore.sh p_reg_testing "MES 2019: Replica Rebuild Registry"