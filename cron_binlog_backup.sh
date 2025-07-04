#!/bin/bash

# SCRIPT: cron_binlog_backup.sh
# AUTHOR: Ben Chambers
# DATE: December 2024
# VERSION: 1.00
# PLATFORM: Linux
# PURPOSE: This script runs every hour via cron job to back up binary logs to another location.

# Test call
# Actually copy the files
# sudo bash -x cron_binlog_backup.sh /var/lib/mysql 3 central
# Dry run to check what is being copied is correct
# sudo bash -x cron_binlog_backup.sh /var/lib/mysql 3 central --dry-run

# Cron Job - Hourly
# 0 */1 * * * sudo bash /root/scripts/cron_binlog_backup.sh /var/lib/mysql 3 av
# 0 */1 * * * sudo bash /root/scripts/cron_binlog_backup.sh /var/lib/mysql 3 central
# 0 */1 * * * sudo bash /root/scripts/cron_binlog_backup.sh /var/lib/mysql/mysqldata 3 s_reg
# 0 */1 * * * sudo bash /root/scripts/cron_binlog_backup.sh /var/lib/mysql 3 e_reg

#find "/var/lib/mysql/binlog.*" -daystart -mtime -1(can be any number but I think 1 to 3 days would do) -print > binarylogs_tobe_backup_up.txt

# Variables
mysql_data_dir=$1
days_to_backup=$2
target_dir_binlog="/data/backups/$3/binlog/$(hostname)"
dry_run=$4
db_server="$(hostname)"
logfile="/data/backups/logs/${db_server}_binlog_backup.log"

# Script
# Creates directory 
mkdir -p "$target_dir_binlog"

# Iterate through binlogs to identify those that should be copied.
binlogs=$(find "$mysql_data_dir"/binlog.* -daystart -mtime -"$days_to_backup" -print)

# Loop through this list to copy them to backup dir
for binlog in $binlogs; do
        echo "$binlog"
        # Checks if dry run flag is present. 
        if [ "$dry_run" == "--dry-run" ]; then
            rsync_options="--list-only"
        else
            rsync_options=""
        fi
        # Copies each binlog to backup directory that satisfies the condition
        if rsync -avrP $rsync_options "$binlog" "$target_dir_binlog" > "$logfile";then
            echo "Successfully Copied $binlog to $target_dir_binlog"
        else
            echo "$db_server - $(date '+%F %T'): Unable to copy $binlog to $target_dir_binlog" | tee -a "$logfile"
            exit 1
        fi
    done;
exit 0