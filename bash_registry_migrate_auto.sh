#!/bin/bash
# SCRIPT: bash_registry_migrate_auto.sh
# AUTHOR: Ben Chambers
# DATE: August 2024
# VERSION: 1.00
# PLATFORM: Linux
# PURPOSE: This script moves domains from the old registry servers to the new MES 2019 environment. It works sequentially, 1 domain at a time
# until all escaped domains in the list have been processed. It logs the duration so timings can be accurately recorded.
# It also performs verification steps at every stage, aborting and logging the failure for any domains missing crucial tables.

# High level steps.
# 1: View of each registry which contains the domain's which are active. 2 columns, 1 which will be the escaped domain, 1 which will be the original name using replace function.
# 2: Populate these into some sort of file, giving something to loop through.
# 3: Variables populated with domain and escaped domain
# 4: While loop that goes through each domain, moving across 1 by one.
# 5: Initial dump and restore of registry db
# 6: Update of isp main and domains table using variables
# 7: Dump and restore of incremental backups
# 8: Call procedure to convert table and data to new structure.

# Pre-requisites.
# 1: The stored procedure 'sp_registry_convert_to_new_format' must be present on the 'message' db on the new environment.
# 2: The message table being moved to must be empty.
# 3: Enough storage must be available on the new environment.
# 4: The up to date vw_domains_not_moving (found in Registry Migration View) should be present on all registry servers. Otherwise the list won't generate.

# Instructions for use:
# 1: Ensure .pass, .pass_c and .pass_p are present with the correct values. These should be the passwords for Nico and reg_rw
# 2: Invoke the bash script entering the following values:
# MES Central DB IP: This should be the IP Address of the central db. If new environment it will be the proxysql ip.
# Primary Registry DB IP: This should be the IP Address of the primary db you are moving FROM.
# Secondary Registry DB IP: This should be the IP Address of the secondary db you are moving FROM.
# New Registry DB IP: This should be the IP Address of the Primary Registry cluster you are moving TO.
# 3: Wait for the script to work through all db's.
# 4: Review the failed domains log for any failures, these will need identifying in the dry run.
# 5: Review the duration log file to check for completion and to note the duration. 

# Example Invocation:
# sudo bash bash_registry_migrate_auto.sh 10.100.23.150 46.175.48.113 77.86.34.113 10.100.23.150
# sudo bash < --script name--           > < central ip > <pri reg ip> <sec reg ip> <new reg ip>

# Notes / Changes:
# Currently set to do a dry run generating the update scripts in a text file rather than running them on central.
# May add a variable to switch dry run on or off.


# -- SCRIPT CONTENTS -- #
# Storage of passwords for used accounts

NICO_PASS=$(< /home/bchambers/.pass.txt)
REG_PASS_2019=$(< /home/bchambers/.pass_p.txt)
#CEN_USER_2019="cen_isp_rw"
CEN_USER_2019="nico"
CEN_PASS_2019=$(< /home/bchambers/.pass_c.txt)
# Define Central, Primary Registry, Secondary registry IP's and new registry ip's. These are inputted by user.
CEN_IP="$1"
PRI_REG_IP="$2"
SEC_REG_IP="$3"
NEW_REG_IP="$4"
# Other variables
TARGET_DIR="/data/registry_move/reg_migration"
LOGFILE=${TARGET_DIR}/migration_log_${PRI_REG_IP}_and_${SEC_REG_IP}.txt
DURATION_LOGFILE=${TARGET_DIR}/migration_duration_log_${PRI_REG_IP}_and_${SEC_REG_IP}.txt
FAILED_DOMAINS=${TARGET_DIR}/failed_domains_${PRI_REG_IP}_and_${SEC_REG_IP}.txt
UPDATE_SCRIPTS=${TARGET_DIR}/update_scripts_${PRI_REG_IP}_and_${SEC_REG_IP}.sql
DATETIME="$(date '+%F %T')"
STARTTIME="$(date '+%T')"
START_MIGRATE="$(date '+%T')"
DOMAIN_MOVING_LIST=${TARGET_DIR}/domain_moving.txt
DOMAIN_NOT_MOVING_LIST=${TARGET_DIR}/domain_not_moving.txt

#function for initial dumper to dump and restore all tables
full_backup_and_restore(){
    local dump_user=$1
    local dump_password=$2
    local restore_user=$3
    local restore_password=$4
    local restore_host=$5

    # Generate comma seperated list that mydumper can use
    # "$TARGET_DIR"/domain_list.txt
    # Puts comma seperated version of domain_list into variable.
    tables_list=$(tr '\n' ',' < "$DOMAIN_MOVING_LIST" | sed 's/,$//')


    # MyDumper L1 Dump
    mydumper --threads 12 \
    --host "$PRI_REG_IP" \
    --user "$dump_user" \
    --password "$dump_password" \
    --rows="20000" \
    --database message \
    --tables-list="$tables_list" \
    --verbose 3 \
    --long-query-guard 999999 \
    --statement-size=1073741824 \
    --less-locking \
    --events \
    --routines \
    --insert-ignore \
    --compress-protocol \
    --outputdir "$TARGET_DIR"/full/"$PRI_REG_IP"_L1_DATA \
    --logfile L1_dump_duration.txt;
   
    # MyDumper L2 Dump
   # mydumper --threads 12 \
   # --host "$SEC_REG_IP" \
   # --user "$dump_user" \
   # --password "$dump_password" \
   # --rows="20000" \
   # --database message \
   # --tables-list="$tables_list" \
   # --verbose 3 \
   # --long-query-guard 999999 \
   # --statement-size=1073741824 \
   # --less-locking \
   # --events \
   # --routines \
   # --insert-ignore \
   # --compress-protocol \
   # --outputdir "$TARGET_DIR"/full/"$SEC_REG_IP"_L2_DATA \
   # --logfile L2_dump_duration.txt;

    # Convert any tables which are myisam to innodb before restore

    sed -i 's/ENGINE=MyISAM/ENGINE=InnoDB/g' "$TARGET_DIR"/full/"$PRI_REG_IP"_L1_DATA/*.sql
    sed -i 's/ENGINE=MyISAM/ENGINE=InnoDB/g' "$TARGET_DIR"/full/"$PRI_REG_IP"_L2_DATA/*.sql

    # Restores
    myloader --threads 12 \
    --host "$restore_host" \
    --user "$restore_user" \
    --password "$restore_password" \
    --database message \
    --directory "$TARGET_DIR"/full/"$PRI_REG_IP"_L1_DATA \
    --queries-per-transaction 10000 \
    --compress-protocol \
    --verbose 3 

 #   myloader --threads 12 \
  #  --host "$restore_host" \
  #  --user "$restore_user" \
  #  --password "$restore_password" \
  #  --database message \
  #  --directory "$TARGET_DIR"/full/"$SEC_REG_IP"_L2_DATA  \
  #  --queries-per-transaction 10000 \
  #  --compress-protocol \
  #  --verbose 3 
}

#function to call to take second incremental backups from old server and restore to new.

incremental_backup_and_restore(){
    local dump_user=$1
    local dump_password=$2
    local restore_user=$3
    local restore_password=$4
    local restore_host=$5

    # Take L1 Dump
    echo -e '===========\nbackup of '$escaped_domain' started at:' $(date) >> L1_dump_duration.txt;mysqldump -u "$dump_user" -p"$dump_password" -h "$domain_pri_ip" --verbose --single-transaction --insert-ignore --no-create-info --skip-add-drop-table --where="``date`` >= 'curdate()' " message "$escaped_domain" --result-file "$TARGET_DIR"/incremental/"$escaped_domain"_L1_DATA.sql; echo -e 'backup of '$escaped_domain' finished at:' $(date) >> L1_dump_duration.txt; sed -i "s/LOCK TABLES \`"$escaped_domain"\` WRITE;//g" "$TARGET_DIR"/incremental/"$escaped_domain"_L1_DATA.sql;

    # Take L2 Dump
    echo -e '===========\nbackup of '$escaped_domain' started at:' $(date) >> L2_dump_duration.txt;mysqldump -u "$dump_user" -p"$dump_password" -h "$domain_sec_ip" --verbose --single-transaction --insert-ignore --no-create-info --skip-add-drop-table --where="``date`` >= 'curdate()' " message "$escaped_domain" --result-file "$TARGET_DIR"/incremental/"$escaped_domain"_L2_DATA.sql; echo -e 'backup of '$escaped_domain' finished at:' $(date) >> L2_dump_duration.txt; sed -i "s/LOCK TABLES \`"$escaped_domain"\` WRITE;//g" "$TARGET_DIR"/incremental/"$escaped_domain"_L2_DATA.sql;
   
    # Restore both dumps, log the failure if unable to.
    if echo -e "===========\nrestore of table: '$escaped_domain' started at:" $(date) >> L1_restore_duration.txt; mysql -u "$restore_user" -p"$restore_password" -h "$restore_host" -e 'source '$TARGET_DIR'/incremental/'$escaped_domain'_L1_DATA.sql; source '$TARGET_DIR'/incremental/'$escaped_domain'_L2_DATA.sql;'  message ; then 
        echo -e "restore of table: '$escaped_domain' completed at:" $(date) >> L1_restore_duration.txt
        echo "$(date '+%F %T'): Incremental dumps backed up and restored to new environment for '$escaped_domain'. Proceeding to update table to new format" | tee -a "$LOGFILE"
        # Call stored procedure to convert table to new format.
        echo "$(date '+%F %T'): Converting to new format for '$escaped_domain'" | tee -a "$LOGFILE"
        # CALL sp_registry_convert_to_new_format('message','worldstate_co_uk', 10000);
        if mysql -u "$restore_user" -p"$restore_password" -h "$restore_host" -e "CALL message.sp_registry_convert_to_new_format('message','$escaped_domain', 250000);";then
            
            ENDTIME="$(date '+%T')"
            echo "$(date '+%F %T'): Migration & conversion finished for '$escaped_domain' at: '$ENDTIME'" | tee -a "$LOGFILE" "$DURATION_LOGFILE"
            
            # Convert STARTTIME and ENDTIME to seconds since the epoch
            START_SECONDS=$(date -d "$STARTTIME" +%s)
            END_SECONDS=$(date -d "$ENDTIME" +%s)

            # Calculate the total migration time in seconds
            TOTAL_SECONDS=$((END_SECONDS - START_SECONDS))

            # Convert total seconds to hours, minutes, and seconds
            TOTAL_TIME=$(printf '%02d:%02d:%02d' $((TOTAL_SECONDS/3600)) $((TOTAL_SECONDS%3600/60)) $((TOTAL_SECONDS%60)))

            echo "$(date '+%F %T'): Total migration time for '$escaped_domain': '$TOTAL_TIME'" | tee -a "$LOGFILE" "$DURATION_LOGFILE"
            return
        else
            echo "$(date '+%F %T'): Conversion to new format failed for '$escaped_domain'. Logging failure" | tee -a "$LOGFILE" "$FAILED_DOMAINS"
            continue
        fi
    else
            # log the error and exit
                echo -e "restore of table: '$escaped_domain' failed at:" $(date) >> L1_restore_duration.txt
                echo -e "'$escaped_domain' failed restoring at:" $(date) >> "$FAILED_DOMAINS"
                continue
    fi
    # Call stored procedure to convert table to new format.
    # getting backup and restore working first.
}

# Logging to show start of process
echo "$(date '+%F %T'): Migration started for '$PRI_REG_IP' and '$SEC_REG_IP' at: '$START_MIGRATE'" | tee -a "$LOGFILE" "$DURATION_LOGFILE"

# Clear the output file, domain not moving list not cleared as this builds up over time
    > "$LOGFILE"
    > "$DURATION_LOGFILE"
    > "$FAILED_DOMAINS"
    > "$DOMAIN_MOVING_LIST"

# Generate list of domains to be parsed


mkdir "$TARGET_DIR"
mkdir "$TARGET_DIR"/full
mkdir "$TARGET_DIR"/incremental

# SQL Query into a file from registry being migrated. View needs to be present on every machine
mysql -u nico -p"$NICO_PASS" -h "$PRI_REG_IP" --skip-column-names -e "SELECT \`TABLE\` FROM \`message\`.\`vw_domains_not_moving\`;" > "$TARGET_DIR"/domain_list.txt

# Iterate through original domain list, identifying domains present on ISP domains that can be moved across. A list will also be generated for domains remaining to be checked afterwards.
while IFS= read -r escaped_domain; do

# Convert underscore to dot for normal domain name 140 uses.
    domain_name="${escaped_domain//_/.}" 
    echo "$domain_name is the non escaped domain"

db_domain_name=$(mysql -u "$CEN_USER_2019" -p"$CEN_PASS_2019" -h "$CEN_IP" -e "SELECT domain FROM \`isp\`.\`domains\` WHERE domain = '$domain_name';" -s -N)
        echo "'$db_domain_name' is the db domain name."
        # Works out if domain exists in DB, converts back to escaped domain prior to adding.
        if
        [[ "$domain_name" == "$db_domain_name" ]]; then
            echo "$(date '+%F %T'): Domain name found in the DB, adding domain to moving list: '$domain_name'" | tee -a "$LOGFILE"
            echo "${domain_name//./_}" >> "$DOMAIN_MOVING_LIST"
            
        else 
            echo "$(date '+%F %T'): Domain name not found in the DB, adding domain to not moving list: '$domain_name'" | tee -a "$LOGFILE"
            echo "${domain_name//./_}" >> "$DOMAIN_NOT_MOVING_LIST"
        fi
done < "$TARGET_DIR"/domain_list.txt


# Initial dump before records updated and tables restored using mydumper, this will move the bulk of the data.

if full_backup_and_restore "nico" "$NICO_PASS" "reg_rw" "$REG_PASS_2019" "$NEW_REG_IP";then
        # While loop that script will sit within
    while IFS= read -r escaped_domain; do
        # Using line as a variable
        echo "Processing '$escaped_domain'"
        # log start time for current domain
        STARTTIME="$(date '+%T')"
        echo "$(date '+%F %T'): Incremental Migration started for '$escaped_domain' at: '$STARTTIME'" | tee -a "$LOGFILE" "$DURATION_LOGFILE"
        # Convert underscore to dot for normal domain name 140 uses.
        domain_name="${escaped_domain//_/.}" 
        echo "$domain_name is the non escaped domain"
    
    # Conditional to confirm that escaped domain can be accessed in primary, secondary and central db. If none can be found, error logged and moves on to next domain

        db_domain_name=$(mysql -u "$CEN_USER_2019" -p"$CEN_PASS_2019" -h "$CEN_IP" -e "SELECT domain FROM \`isp\`.\`domains\` WHERE domain = '$domain_name';" -s -N)
        echo "'$db_domain_name' is the db domain name."
        if
        [[ "$domain_name" == "$db_domain_name" ]]; then
            echo "$(date '+%F %T'): Domain name found in the DB, continuing migration for '$domain_name'" | tee -a "$LOGFILE"
            
            # Load Primary IP and Secondary IP into variables using view on 140
            domain_pri_ip=$(mysql -u "$CEN_USER_2019" -p"$CEN_PASS_2019" -h "$CEN_IP" -e "SELECT primaryregistry FROM \`isp\`.\`v_domain_registry\` WHERE domain = '$domain_name';" -s -N)
            domain_sec_ip=$(mysql -u "$CEN_USER_2019" -p"$CEN_PASS_2019" -h "$CEN_IP" -e "SELECT secondaryregistry FROM \`isp\`.\`v_domain_registry\` WHERE domain = '$domain_name';" -s -N)
            echo "$(date '+%F %T'): '$domain_pri_ip' is the primary registry and '$domain_sec_ip' is the secodnary registry for '$domain_name'" | tee -a "$LOGFILE"

                #L1 & L2 data restoring to primary cluster
                
                    echo "$(date '+%F %T'): Initial dumps backed up and restored to new environment for '$escaped_domain'. Proceeding to update isp tables." | tee -a "$LOGFILE"
                    #Update records in mysql, note for testing these will just be echos.
                    # Select various validation measures into variables.
                    account_type=$(mysql -u nico -p"$NICO_PASS" -h "$CEN_IP" -e "SELECT \`smtpusername\` FROM \`isp\`.\`domains\` WHERE \`domain\` = '$domain_name';" -s -N) #smtpusername field being exchangeholding or null means its hex. Anything else on prem
                    user_domain=$(mysql -u nico -p"$NICO_PASS" -h "$CEN_IP" -e "SELECT DISTINCT SUBSTRING_INDEX(\`username\`,'@',-1) FROM \`isp\`.\`main\`WHERE SUBSTRING_INDEX(\`username\`,'@',-1) = '$domain_name';" -s -N)
                    
                    echo "$account_type"
                    echo "$user_domain"
                    # Confirm if the current primary account is an exchange or on prem.
                    if [[ "$account_type" == 'exchangeholding' ]] || [[ -z "$account_type" ]];then
                        #Set domains and main to the primaryaccountid of 'mes99999999' (Hosted Exchange)
                        echo "UPDATE \`isp\`.\`main\` SET memberof = 'mes99999999' WHERE SUBSTRING_INDEX(\`username\`,'@',-1) = '$domain_name';" | tee -a "$UPDATE_SCRIPTS"
                        echo "UPDATE \`isp\`.\`domains\` SET primaryaccountid = 'mes99999999' WHERE domain = '$domain_name';" | tee -a "$UPDATE_SCRIPTS"

                        #Call function to dump & restore incremental backups
                        incremental_backup_and_restore "nico" "$NICO_PASS" "reg_rw" "$REG_PASS_2019" "$NEW_REG_IP"
                        
                    else
                        #Set domains and main to the primaryaccountid of 'mes99999998' (On Prem)
                        echo "UPDATE \`isp\`.\`main\` SET memberof = 'mes99999998' WHERE SUBSTRING_INDEX(\`username\`,'@',-1) = '$domain_name';" | tee -a "$UPDATE_SCRIPTS"
                        echo "UPDATE \`isp\`.\`domains\` SET primaryaccountid = 'mes99999998' WHERE domain = '$domain_name';" | tee -a "$UPDATE_SCRIPTS"

                        #Call function to dump & restore incremental backups
                        incremental_backup_and_restore "nico" "$NICO_PASS" "reg_rw" "$REG_PASS_2019" "$NEW_REG_IP"
                        
                    fi
                    # Confirm the domain part of the username matches the domain name.
                    # After passing both of these checks, update the primary account id with the new value in isp.main and isp.domains
            
        else
            echo "$(date '+%F %T'): Domain name not found in the DB, stopping migration for '$domain_name'" | tee -a "$LOGFILE"
            echo -e "'$escaped_domain' not found at:" $(date) >> "$FAILED_DOMAINS"
            continue
        fi


    done < "$DOMAIN_MOVING_LIST"
else
    echo "$(date '+%F %T'): Initial mydumper of DB's moving across failed. Aborting" | tee -a "$LOGFILE"
    exit 1
fi

END_MIGRATE="$(date '+%T')"

echo "$(date '+%F %T'): Migration finished for '$PRI_REG_IP' and '$SEC_REG_IP' at: '$END_MIGRATE'" | tee -a "$LOGFILE" "$DURATION_LOGFILE"
        
        # Convert STARTTIME and ENDTIME to seconds since the epoch
        M_START_SECONDS=$(date -d "$START_MIGRATE" +%s)
        M_END_SECONDS=$(date -d "$END_MIGRATE" +%s)

        # Calculate the total migration time in seconds
        M_TOTAL_SECONDS=$((M_END_SECONDS - M_START_SECONDS))

        # Convert total seconds to hours, minutes, and seconds
        M_TOTAL_TIME=$(printf '%02d:%02d:%02d' $((M_TOTAL_SECONDS/3600)) $((M_TOTAL_SECONDS%3600/60)) $((M_TOTAL_SECONDS%60)))

echo "$(date '+%F %T'): Total migration time for '$PRI_REG_IP' and '$SEC_REG_IP'= '$M_TOTAL_TIME'" | tee -a "$LOGFILE" "$DURATION_LOGFILE"


exit 0


