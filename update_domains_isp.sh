#!/bin/bash
# SCRIPT: bash_isp_update_registry_create
# AUTHOR: Ben Chambers
# DATE: August 2024
# VERSION: 1.00
# PLATFORM: Linux
# PURPOSE: This script updates all main and domain accounts to the new MES2019 primary accounts. It will also create the new table structures 
# to use going forward. It will not move any data as that will be done as a seperate process.

# High level steps:
# 1: Create new table structure on MES 2019 DB registry.
# 2: Update primaryaccountid / memberof for all domains in view.
# 3: View needs to exclude any tables that we are not moving across the registry for.

# Instructions:
# 1: Ensure password variables are stored in the referenced locations
# 2: Ensure domain list is present and up to date. (from spreadsheet: )

# Example Invocation:
# sudo bash -x bash_registry_migrate_update_isp 46.175.48.141 10.100.23.110

# Changes / Notes:
#

# Variables:
NICO_PASS=$(< /home/bchambers/.pass.txt)
REG_USER_2019="reg_rw"
REG_PASS_2019=$(< /home/bchambers/.pass_p.txt)
CEN_USER_2019="cen_isp_rw"
#CEN_USER_2019="nico"
CEN_PASS_2019=$(< /home/bchambers/.pass_c.txt)
# Define Central and new registry ip's. These are inputted by user.
CEN_IP="$1"
NEW_REG_IP="$2"
# Other variables
TARGET_DIR="/home/bchambers"
LOGFILE=${TARGET_DIR}/migration_log_bash_isp_update_registry_create.txt
DURATION_LOGFILE=${TARGET_DIR}/migration_duration_log_bash_isp_update_registry_create.txt
FAILED_DOMAINS=${TARGET_DIR}/failed_domains_bash_isp_update_registry_create.txt
UPDATE_SCRIPTS=${TARGET_DIR}/update_scripts_bash_isp_update_registry_create.sql
STARTTIME="$(date '+%T')"

# Clear the output file
    > "$LOGFILE"
    > "$DURATION_LOGFILE"
    > "$FAILED_DOMAINS"
	> "$UPDATE_SCRIPTS"

# Functions:
registry_create_tables(){
local escaped_domain="${domain//./_}"

# MySQL Queries Stored as variables
QUERY=$(cat <<EOF 
SET @db = 'message_BC_testing';
SET @tab = '$escaped_domain';

	# Creates new tables for the data to move to.
	SET @create_email_sql = CONCAT(
			"CREATE TABLE IF NOT EXISTS \`",@db,"\`.\`",@tab,"_email_details\` (
			\`emailid\` varchar(48) NOT NULL,
			\`date\` date DEFAULT NULL,
			\`time\` time DEFAULT NULL,
			\`datecode\` int DEFAULT NULL,
			\`subject\` varchar(128) DEFAULT NULL,
			PRIMARY KEY (\`emailid\`) USING BTREE,
			KEY \`idx_emailid_date\` (\`emailid\`,\`date\`),
			KEY \`idx_date\` (\`date\`),
			KEY \`idx_email_datecode\` (\`emailid\`,\`datecode\`),
			KEY \`idx_datecode\` (\`datecode\`)
			);"	
		);

		PREPARE create_email_stmt FROM @create_email_sql;
		EXECUTE create_email_stmt;
		DEALLOCATE PREPARE create_email_stmt;
  
		SET @create_archive_sql = CONCAT(
			"CREATE TABLE IF NOT EXISTS \`",@db,"\`.\`",@tab,"_archive\` (
			\`emailid\` varchar(48) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
			\`location\` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
			\`archivestatus\` char(1) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
			\`archivestatus2\` char(1) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
			\`archiveserver1\` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
			\`archiveserver2\` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
			PRIMARY KEY (\`emailid\`) USING BTREE,
			CONSTRAINT \`fk_",@tab,"_arc_emailid\` FOREIGN KEY (\`emailid\`) REFERENCES \`",@db,"\`.\`",@tab,"_email_details\` (\`emailid\`)
			) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;"
		);
		PREPARE create_archive_stmt FROM @create_archive_sql;
		EXECUTE create_archive_stmt;
		DEALLOCATE PREPARE create_archive_stmt;
    
		SET @create_misc_sql = CONCAT(
			"CREATE TABLE IF NOT EXISTS \`",@db,"\`.\`",@tab,"_misc\` (
			\`emailid\` varchar(48) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
			\`size\` int DEFAULT NULL,
			\`countrychain\` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
			\`originip\` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
			PRIMARY KEY (\`emailid\`) USING BTREE,
			CONSTRAINT \`fk_",@tab,"misc_emailid\` FOREIGN KEY (\`emailid\`) REFERENCES \`",@db,"\`.\`",@tab,"_email_details\` (\`emailid\`)
			) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;"
		);
			PREPARE create_misc_stmt FROM @create_misc_sql;
			EXECUTE create_misc_stmt;
			DEALLOCATE PREPARE create_misc_stmt;
    
		SET @create_participants_sql = CONCAT(
			"CREATE TABLE IF NOT EXISTS \`",@db,"\`.\`",@tab,"_participants\` (
			\`emailid\` varchar(48) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
			\`emailto\` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
			\`emailfrom\` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
			\`direction\` char(1) DEFAULT NULL,
			PRIMARY KEY (\`emailid\`) USING BTREE,
			KEY \`idx_wp_emailto_direction\` (\`emailto\`,\`direction\`),
			KEY \`idx_wp_emailfrom_direction\` (\`emailfrom\`,\`direction\`),
			CONSTRAINT \`fk_",@tab,"emailid\` FOREIGN KEY (\`emailid\`) REFERENCES \`",@db,"\`.\`",@tab,"_email_details\` (\`emailid\`)
			) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;"
			);
			PREPARE create_participants_stmt FROM @create_participants_sql;
			EXECUTE create_participants_stmt;
			DEALLOCATE PREPARE create_participants_stmt;


			SET @create_spam_sql = CONCAT(
				"CREATE TABLE IF NOT EXISTS \`",@db,"\`.\`",@tab,"_spam_details\` (
				\`emailid\` varchar(48) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
				\`held\` char(1) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
				\`spamscore\` int DEFAULT NULL,
				\`spamtests\` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL,
				PRIMARY KEY (\`emailid\`) USING BTREE,
				CONSTRAINT \`fk_",@tab,"spam_emailid\` FOREIGN KEY (\`emailid\`) REFERENCES \`",@db,"\`.\`",@tab,"_email_details\` (\`emailid\`)
				) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;"
			);
			PREPARE create_spam_stmt FROM @create_spam_sql;
			EXECUTE create_spam_stmt;
			DEALLOCATE PREPARE create_spam_stmt;


			SET @viewcreate = CONCAT(
                "create or replace view   \`",@db,"\`.\`",@tab,"\` as
				select e.emailid, p.emailto, p.emailfrom, p.direction, s.held, e.date, e.time, e.datecode,
				e.subject, s.spamscore, s.spamtests, a.location, m.size, m.countrychain, m.originip,
				a.archivestatus, a.archivestatus2, a.archiveserver1, a.archiveserver2
				from \`",@db,"\`.\`",@tab,"_email_details\` e
				join \`",@db,"\`.\`",@tab,"_archive\` a on a.emailid=e.emailid
				join \`",@db,"\`.\`",@tab,"_misc\` m on m.emailid=e.emailid
				join \`",@db,"\`.\`",@tab,"_participants\` p on p.emailid=e.emailid
				join \`",@db,"\`.\`",@tab,"_spam_details\` s on s.emailid=e.emailid;"
                );
                
			PREPARE viewcreate_stmt FROM @viewcreate;
            EXECUTE viewcreate_stmt;
            DEALLOCATE PREPARE viewcreate_stmt;
EOF
)

	# Run mysql scripts to create tables and view on new server
	mysql -u "$REG_USER_2019" -p"$REG_PASS_2019" -h "$NEW_REG_IP" -e "$QUERY"
}

isp_update_domains(){
	account_type=$(mysql -u "$CEN_USER_2019" -p"$CEN_PASS_2019" -h "$CEN_IP" -e "SELECT \`smtpusername\` FROM \`isp\`.\`domains\` WHERE \`domain\` = '$domain';" -s -N) #smtpusername field being exchangeholding or null means its hex. Anything else on prem
                user_domain=$(mysql -u "$CEN_USER_2019" -p"$CEN_PASS_2019" -h "$CEN_IP" -e "SELECT DISTINCT SUBSTRING_INDEX(\`username\`,'@',-1) FROM \`isp\`.\`main\`WHERE SUBSTRING_INDEX(\`username\`,'@',-1) = '$domain';" -s -N)
                
                echo "$account_type"
                echo "$user_domain"
                # Confirm if the current primary account is an exchange or on prem.
                if [[ "$account_type" == 'exchangeholding' ]] || [[ -z "$account_type" ]];then
                    #Set domains and main to the primaryaccountid of 'mes99999999' (Hosted Exchange)
                    echo "UPDATE \`isp\`.\`main\` SET memberof = 'mes99999999' WHERE SUBSTRING_INDEX(\`username\`,'@',-1) = '$domain';" | tee -a "$UPDATE_SCRIPTS"
                    echo "UPDATE \`isp\`.\`domains\` SET primaryaccountid = 'mes99999999' WHERE domain = '$domain';" | tee -a "$UPDATE_SCRIPTS"

                    
                else
                    #Set domains and main to the primaryaccountid of 'mes99999998' (On Prem)
                    echo "UPDATE \`isp\`.\`main\` SET memberof = 'mes99999998' WHERE SUBSTRING_INDEX(\`username\`,'@',-1) = '$domain';" | tee -a "$UPDATE_SCRIPTS"
                    echo "UPDATE \`isp\`.\`domains\` SET primaryaccountid = 'mes99999998' WHERE domain = '$domain';" | tee -a "$UPDATE_SCRIPTS"

                fi
}
# Requires domain list to be manually populated using current spreadsheet.

# Script Start Time
STARTTIME="$(date '+%T')"
echo "$(date '+%F %T'): Beginning script: start time = '$STARTTIME"| tee -a "$LOGFILE" "$DURATION_LOGFILE"
while IFS= read -r domain; do

		echo "$(date '+%F %T'): Table creation successful for '$domain'. Proceeding to update ISP with new primary account."| tee -a "$LOGFILE"
		if isp_update_domains; then
			echo "$(date '+%F %T'): Primary account updated for '$domain'. Proceeding to next domain."| tee -a "$LOGFILE"
		else
			echo "$(date '+%F %T'): Unable to update primary account for '$domain'. Logging failure and proceeding to next domain."| tee -a "$LOGFILE" "$FAILED_DOMAINS"
			continue
		fi

done < "$TARGET_DIR"/domain_list.txt
# Script End Time and Duration:

ENDTIME="$(date '+%T')"
echo "$(date '+%F %T'): Script finish time = '$ENDTIME"| tee -a "$LOGFILE" "$DURATION_LOGFILE"

        # Convert STARTTIME and ENDTIME to seconds since the epoch
        START_SECONDS=$(date -d "$STARTTIME" +%s)
        END_SECONDS=$(date -d "$ENDTIME" +%s)

        # Calculate the total migration time in seconds
        TOTAL_SECONDS=$((END_SECONDS - START_SECONDS))

        # Convert total seconds to hours, minutes, and seconds
        TOTAL_TIME=$(printf '%02d:%02d:%02d' $((TOTAL_SECONDS/3600)) $((TOTAL_SECONDS%3600/60)) $((TOTAL_SECONDS%60)))

echo "$(date '+%F %T'): Total runtime for script= '$TOTAL_TIME'" | tee -a "$LOGFILE" "$DURATION_LOGFILE"
exit 0