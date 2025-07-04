#!/bin/bash

# Purpose: This script takes a daily backup of the ProxySQL configuration. The backup is written to a config file which can be restored 
# to another instance of proxysql.
#
# Build strategy
# 1: Get proxysql backup functioning and logging correctly, test this. -done
# 2: Once backup is functioning, add this within some conditional logic so that script errors suitably. -done
# 3: Add rotating elements so old backups are removed -done
#
# Considerations
# 1: Once backup working, add a means to encrypt it. - done

# To restore:
# sudo gpg --output /data/backups/proxysql/restore.cnf -d /data/backups/proxysql/mes-l2-psql-01-2024-05-29.cnf.gpg

# Set Variables
defaults_file="/etc/.proxy_backup_defaults.cnf"
target_dir="/data/backups/proxysql"
todays_backup="${target_dir}/$(hostname)-$(date +%F).cnf"
logfile="/data/cron_proxysql_backup.log"
encrypt_file_loc="/data/.keyfile"
retention_period="28"
password_length="20"

# Completes backup, log's successful backup.
USER=$(stat -c '%U' $target_dir)
# Checks that backup directory is owned by proxysql
if #backup dir is owned by proxysql do this
[[ $USER == "proxysql" ]];then
    mysql --defaults-file="$defaults_file" -P 6032 -e "select config into outfile $todays_backup;"
    echo "$(date '+%F %T'): Config file successfully backed up and can be found in $todays_backup. " | tee -a "$logfile"
    password=$(grep -oP '\w{'$password_length'}' "$defaults_file")
    echo "DEBUG: password is $password"
    
    #Check to see if password was found.
    if
        [[ -n "$password" ]];then
        echo "$(date '+%F %T'): Password successfully taken from config file, commencing encryption with this password." | tee -a "$logfile"
        gpg --batch --yes --passphrase "$password" -c "$todays_backup"
        #Check if encrypted backup exists, confirm this and remove any backups older than retention period.
            if 
            [[ -e $todays_backup.gpg ]];then
                echo "$(date '+%F %T'): $todays_backup.gpg successfully encrypted. Proceeding to remove original and any backups older than retention period. " | tee -a "$logfile"
                rm "$todays_backup"
                find "$target_dir" -mtime +"$retention_period" -exec rm -rf {} \;
                echo "$(date '+%F %T'): Original file and ProxySQL backups older than $retention_period days removed" | tee -a "$logfile"
                exit 0
            else #encrypted backup doesn't exist
                echo "$(date '+%F %T'): $todays_backup.gpg not found. Encryption unsuccessful, check that $defaults_file contains a password." | tee -a "$logfile"
                exit 1
            fi
    else
        echo "$(date '+%F %T'): Password not correctly, check that $defaults_file contains a 20 character password." | tee -a "$logfile"
        exit 1
    fi

else #error message
    echo "$(date '+%F %T'): Backup directory not owned by proxysql, please check $target_dir is owned by proxysql " | tee -a "$logfile"
    exit 1
fi


