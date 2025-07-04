#!/bin/bash
# SCRIPT: bash_mydumper_convert_myloader.sh
# AUTHOR: Ben Chambers
# DATE: September 2024
# VERSION: 1.00
# PLATFORM: Linux
# PURPOSE: This script takes a mydumper from the source IP, converts all MyISAM Tables to innodb,
# removes additional indexes, restores to seperate message db ready for conversion.


# High level steps:
# 1: Using a list as an input. Create a mydumper of all DB's being moved across to MES2019.
# 2: Convert any MyISAM tables to InnoDB.
# 3: Remove all additional indexes, leaving only the primary key to speed up restore.
# 4: Restore dump to DB using myloader.

# Prerequisites:
# 1: On the restore server, max_allowed_packet should match what the mydumper is configured to (below uses the maximum: )
# 2: Setting threads too high will cause OOM error, especially if 3 big tables are being loaded at the same time. 3 threads seems optimal.
# Instructions:
# 

# Example Invocation:
# sudo bash -x bash_mydumper_convert_myloader.sh 10.100.23.101 10.200.23.150 4 4
# sudo bash -x bash_mydumper_convert_myloader.sh 10.200.10.191 10.200.23.150 4 4
# sudo bash -x bash_mydumper_convert_myloader.sh 10.200.10.191 10.100.23.110 4 4

# Changes / Notes:
# 1.01 - changed sed command from sed -i '/KEY `IX_/d' "$file" to  sed -i '/KEY `/d' "$file". This is to capture indexes using non standard naming.
# 1.01 - commented out rm -rf as it was deleting the dumps while the restore was still running for now.

# Variables:
REG_USER="nico"
REG_PASS=$(< /home/bchambers/.pass.txt)
REG_USER_2019="reg_rw"
REG_PASS_2019=$(< /home/bchambers/.pass_p.txt)

# Define source IP, destination IP and amount of threads to use for dump & restore. (These are inputted by user)
SOURCE_IP="$1"
DEST_IP="$2"
DUMP_THREADS="$3"
REST_THREADS="$4"
SET_NUMBER="$5"

# Location of list of domains being moved
DOMAIN_LIST="/home/bchambers/domain_list_${SET_NUMBER}.txt"
ESCAPED_DOMAIN_LIST="/home/bchambers/escaped_domain_list_${SET_NUMBER}.txt"


# Other variables
TARGET_DIR="/data/registry_move/reg_migration"
TARGET_DIR="${TARGET_DIR}/${SOURCE_IP}"
LOGFILE="/data/registry_move/reg_migration/${SOURCE_IP}_backup_and_restore_log.log"
DOMAIN_MOVING_LIST=${TARGET_DIR}/domain_moving.txt

STARTTIME="$(date '+%T')"

# Clear the output file
    > "$LOGFILE"

# Functions:
#function for initial dumper to dump and restore all tables
mydumper_func(){

    # Generate comma seperated list that mydumper can use
    # "$TARGET_DIR"/domain_list.txt
    # "$DOMAIN_LIST"
    # Puts comma seperated version of domain_list into variable.
    # unquoted_domain_moving_list=$(echo $DOMAIN_MOVING_LIST | sed)

    tables_list=$(tr '\n' ',' < "$DOMAIN_MOVING_LIST" | sed "s/'//g")


    # MyDumper Dump
    mydumper --threads "$DUMP_THREADS" \
    --host "$SOURCE_IP" \
    --user "$REG_USER" \
    --password "$REG_PASS" \
    --rows="20000" \
    --database message \
    --tables-list="$tables_list" \
    --verbose 3 \
    --long-query-guard 999999 \
    --statement-size=536870912 \
    --less-locking \
    --events \
    --routines \
    --insert-ignore \
    --compress-protocol \
    --outputdir "$TARGET_DIR" >> "$LOGFILE" 2>&1;
   
   
    # Convert any tables which are myisam to innodb before restore

    sed -i 's/ENGINE=MyISAM/ENGINE=InnoDB/g' "$TARGET_DIR"/*-schema.sql
    sed -i 's/PRIMARY KEY (`emailid`),/PRIMARY KEY (`emailid`)/g' "$TARGET_DIR"/*-schema.sql

    # Loop through each SQL file in the directory
    for file in "$TARGET_DIR"/*-schema.sql; do
        # Use sed to remove lines containing secondary indexes
        sed -i '/^  KEY `/d' "$file"
    done
}

myloader_func(){
        # Restore the converted DB to the destination server
    myloader --threads "$REST_THREADS" \
    --host "$DEST_IP" \
    --user "$REG_USER_2019" \
    --password "$REG_PASS_2019" \
    --database message_orig \
    --directory "$TARGET_DIR" \
    --queries-per-transaction 10000 \
    --compress-protocol \
    --verbose 3 >> "$LOGFILE" 2>&1


}
# Make target dir
mkdir "$TARGET_DIR"

# Convert domain list to escaped domains, parse this for domains being moved.

sed 's/\./_/g' "$DOMAIN_LIST" > "$ESCAPED_DOMAIN_LIST"

# Check each escaped domain against the information_schema. Found domains added to a list for mydumper.

while IFS= read -r domain_name; do
db_domain_name=$(mysql -u "$REG_USER" -p"$REG_PASS" -h "$SOURCE_IP" -e "SELECT TABLE_NAME FROM \`information_schema\`.\`tables\` WHERE table_schema = 'message' AND table_type = 'BASE TABLE' AND table_name = '$domain_name';" -s -N)
        echo "'$db_domain_name' is the db domain name."
        if [[ "$domain_name" == "$db_domain_name" ]]; then
            echo "$(date '+%F %T'): Escaped domain found in the DB, adding domain to moving list: '$domain_name'" | tee -a "$LOGFILE"
            echo "'$domain_name'" >> "$DOMAIN_MOVING_LIST"
        else 
            echo "$(date '+%F %T'): Escaped domain not found in the DB, skipping: '$domain_name'" | tee -a "$LOGFILE"
            continue
        fi
done < "$ESCAPED_DOMAIN_LIST"

# Parsed list for DB's now generated, commence mydumper
# Call function that executes mydumper
if mydumper_func; then
    # Proceed to run myloader
    if myloader_func; then
        echo "$(date '+%F %T'): Tables successfully restored, proceeding to conversion to new format." | tee -a "$LOGFILE"
        
        
    else
        # Error message generated if myloader unable to be run
        echo "$(date '+%F %T'): Unable to run myloader, exiting" | tee -a "$LOGFILE"
        exit 1
    fi

else
    # Error message generated if mydumper unable to be run
    echo "$(date '+%F %T'): Unable to run mydumper, exiting" | tee -a "$LOGFILE"
    exit 1
fi

# Generate fresh list for stored procedure to loop through
while IFS= read -r domain_convert; do
    echo "$(date '+%F %T'): Calling stored procedure to convert '$domain_convert'." | tee -a "$LOGFILE"
    
    # Call stored procedure to convert the table to the new format.
    if mysql -u "$REG_USER_2019" -p"$REG_PASS_2019" -h "$DEST_IP" -e "CALL message.sp_registry_convert_to_new_format('message','message_orig',$domain_convert, 100000);";then
        #this
        echo "$(date '+%F %T'): Conversion successful for '$domain_convert'. Moving on to next domain." | tee -a "$LOGFILE"
    else
        #this
        echo "$(date '+%F %T'): Conversion unsuccessful for '$domain_convert'. Logging failure and moving on to next domain." | tee -a "$LOGFILE"
        continue
    fi
done < "$DOMAIN_MOVING_LIST"

# All steps now complete, clearing dump data and logging time taken.

# rm -rf "$TARGET_DIR"

ENDTIME="$(date '+%T')"
echo -e "-------------------------------\n\n"
echo "$(date '+%F %T'): Script start time = '$STARTTIME'"| tee -a "$LOGFILE"
echo "$(date '+%F %T'): Script finish time = '$ENDTIME'"| tee -a "$LOGFILE"

        # Convert STARTTIME and ENDTIME to seconds since the epoch
        START_SECONDS=$(date -d "$STARTTIME" +%s)
        END_SECONDS=$(date -d "$ENDTIME" +%s)

        # Calculate the total migration time in seconds
        TOTAL_SECONDS=$((END_SECONDS - START_SECONDS))

        # Convert total seconds to hours, minutes, and seconds
        TOTAL_TIME=$(printf '%02d:%02d:%02d' $((TOTAL_SECONDS/3600)) $((TOTAL_SECONDS%3600/60)) $((TOTAL_SECONDS%60)))

echo "$(date '+%F %T'): Total runtime for script= '$TOTAL_TIME'" | tee -a "$LOGFILE"
exit 0
