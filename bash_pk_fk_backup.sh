#!/bin/bash

# High level steps

# 1: Find list of tables to loop through, using the views
# 2: Begin loop
# 3: Using the VIEW, obtain a list of Primary Keys, store these in a text file. (Where emailid has date equal or less than )
# 4: Dump each sub table using the primary key text file as a lookup

# Set Variables:
db_schema='message'
logfile=/usr/app/logs/pk_fk_backup_`date +%d%m%Y`.log
defaults_file='--defaults-file=/home/bchambers/.my.cnf'
# List of domains to loop through
domains_txt='/var/lib/mysql-files/domains.txt'
dump_dir='/data/backups/p_reg_inconsistent_backupserver'

# 1 Identifying tables to loop through
# After 28th april - when we need records older than
# Log script start time
scriptstart=`date +%d%m%Y::%X`

# Create the dump dir if it doesn't exist
mkdir $dump_dir
# Function to go through each domain, selecting the relevant email id's.
# It then dumps the parent and child tables, filtering for the identified email id's
table_dump_looper(){
    while IFS= read -r line; do
        echo "Processing: $line"
        
        local domains_emailidlist='/var/lib/mysql-files/domainsemailid.txt'
        local query="
            select emailid from \`$db_schema\`.\`$line\` 
            where \`date\` >= '2025-04-28'
            INTO OUTFILE '$domains_emailidlist'
                FIELDS TERMINATED BY ',' ENCLOSED BY '\''
                LINES TERMINATED BY ',\n';
        "
        rm $domains_emailidlist
        # This gets the list of email id's that we want the dump to grab. 
        # Note that the view is used so only consistent records are dumped.
        mysql $defaults_file -e "$query" --skip-column-names

        # Remove last comma and new line from the output file
        sed -i '$ s/,$//' $domains_emailidlist

        # We only do the dumps if there are email id's to dump.
        if [[ -s $domains_emailidlist ]];then
            
            emailid=$(cat $domains_emailidlist)
            # Variables for mysqldump
            local mysqldump_options=(
            '--insert-ignore'
            '--no-create-db'
            '--no-create-info'
            '--single-transaction'
            '--set-gtid-purged=OFF'
            "--where=emailid in ($emailid)"
            )
            local mydumper_options=(
            '--insert-ignore'
            '--trx-consistency-only'
            '--no-schemas'
            '--rows=1000'
            '--dirty'
            '--compress-protocol'
            '--threads=4'
            "--outputdir=$dump_dir"
            "--where=emailid in ($emailid)"
            )
            mydumper $defaults_file "${mydumper_options[@]}" --tables-list=$db_schema."$line"_email_details
            mydumper $defaults_file "${mydumper_options[@]}" --tables-list=$db_schema."$line"_archive 
            mydumper $defaults_file "${mydumper_options[@]}" --tables-list=$db_schema."$line"_misc
            mydumper $defaults_file "${mydumper_options[@]}" --tables-list=$db_schema."$line"_participants
            mydumper $defaults_file "${mydumper_options[@]}" --tables-list=$db_schema."$line"_spam_details
            #mysqldump $defaults_file "${mysqldump_options[@]}" $db_schema "$line"_email_details > $dump_dir/"$line"_email_details.sql
            #mysqldump $defaults_file "${mysqldump_options[@]}" $db_schema "$line"_archive > $dump_dir/"$line"_archive.sql
            #mysqldump $defaults_file "${mysqldump_options[@]}" $db_schema "$line"_misc > $dump_dir/"$line"_misc.sql
            #mysqldump $defaults_file "${mysqldump_options[@]}" $db_schema "$line"_participants > $dump_dir/"$line"_participants.sql
            #mysqldump $defaults_file "${mysqldump_options[@]}" $db_schema "$line"_spam_details > $dump_dir/"$line"_spam_details.sql
            sleep 2
        else
            echo "$(date '+%F %T'): $line doesn't have any records. Skipping." | tee -a "$logfile"
        fi


    done < "$domains_txt"
}

rm $domains_txt
if mysql $defaults_file -e "select TABLE_NAME from information_schema.tables where table_schema = 'message' and table_type = 'VIEW' INTO OUTFILE '$domains_txt';" --skip-column-names;then
    echo "$(date '+%F %T'): List of tables successfully retrieved, progressing" | tee -a "$logfile"
    table_dump_looper
else
    echo "$(date '+%F %T'): Table list unable to be gathered. Exiting" | tee -a "$logfile"
    exit 1
fi
# Log script end time
scriptend=`date +%d%m%Y::%X`
echo "$(date '+%F %T'): All tables identified and dumped. Started at $scriptstart, finished at $scriptend" | tee -a "$logfile"