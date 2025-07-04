#!/bin/bash

# SCRIPT: orchestrator_post_failover.sh
# AUTHOR: Ben Chambers
# DATE: March 2025
# VERSION: 1.00
# PLATFORM: Linux
# PURPOSE: This script sets the failed master as offline within ProxySQL 
# and notifies DBA teams channel that a failover has needed to take place.

# Variables needing to be passed to script from orchestrator
#{failedHost}
#{failedPort}
#{successorHost}
#{successorPort}

# Test script:
# sudo bash orchestrator_post_failover.sh {failedHost},{failedPort},{successorHost},{successorPort},'MES 2019: Registry Replication'
# sudo bash orchestrator_post_failover.sh "{failedHost}","{failedPort}","{successorHost}","{successorPort}","MES 2019: Registry Replication"
# Define and set variables:
proxysql_defaults="/root/.my.cnf"
failedhost=$1
failedport=$2
successorhost=$3
successorport=$4
environment=$5
logfile="/tmp/recovery.log"
#Teams channel is 'DBA Service Alerts'
teams_channel="https://gwncsp.webhook.office.com/webhookb2/b1ddda3d-19cf-4585-92f4-5787c6098eaa@2f0e80a6-80a9-4c92-8401-b2711c15efdc/IncomingWebhook/52190dacc79d487c900bc6ec3e2ca25d/6d1535ef-be9f-4aa2-89a6-b9b22e6148e2/V2rsoe5B8HjVBfKHHOf6PZ8KKehlcHKMB3VHUa17-_lgI1"


# ProxySQL Generate Switch Offline
proxysql_switch_off(){
    local sqlscript="
    UPDATE 'mysql_servers' SET status = 'OFFLINE_SOFT', max_connections = 0 WHERE hostname = '$failedhost';
    LOAD MYSQL SERVERS TO RUNTIME;
    "
    if mysql --defaults-file=$proxysql_defaults -e "$sqlscript" >> "$logfile";then
        echo "$(hostname) - $(date '+%F %T'): $failedhost successfully marked as offline." | tee -a $logfile
    else
        echo "$(hostname) - $(date '+%F %T'): $failedhost unsuccessfully marked as offline" | tee -a $logfile
        exit 1
    fi
}

# Generate post failure scripts to redeploy old master as slave.
teams_notification(){
    message=$(echo -e "**Environment**: $environment \n\n -----------------  \n\n **Replication Failover:** \n\n **Failed Master / Source:** $failedhost:$failedport \n\n **New Master / Source:** $successorhost:$successorport \n\n **Further Information: Orchestrator has failed over to a new master and marked the old master offline in ProxySQL.\n\n The old master will need adding back to the topology and bringing back online. \n\n")
    curl -H "Content-Type: application/json" -d "{\"text\": \"$message\"}" $teams_channel
}

proxysql_switch_off
teams_notification
exit 0