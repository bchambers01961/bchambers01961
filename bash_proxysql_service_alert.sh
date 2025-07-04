#!/bin/bash
# SCRIPT: bash_proxysql_service_alert.sh
# AUTHOR: Ben Chambers
# DATE: October 2024
# VERSION: 1.00
# PLATFORM: Linux
# PURPOSE: This is a simple script which sends an alert to the DBA Service Alerts teams channel if ProxySQL isn't working.

# Variables:
teams_channel="https://gwncsp.webhook.office.com/webhookb2/b1ddda3d-19cf-4585-92f4-5787c6098eaa@2f0e80a6-80a9-4c92-8401-b2711c15efdc/IncomingWebhook/52190dacc79d487c900bc6ec3e2ca25d/6d1535ef-be9f-4aa2-89a6-b9b22e6148e2/V2rsoe5B8HjVBfKHHOf6PZ8KKehlcHKMB3VHUa17-_lgI1"
environment="MES 2019 DB: ProxySQL"
host="$(hostname)"
#Functions:
teams_notification(){
local DATETIME="$(date '+%F %T')"

    message=$(echo -e "**Environment**: $environment \n\n -----------------  \n\n **ProxySQL Service Not Running:** \n\n The ProxySQL service is not running on $host")

    curl -H "Content-Type: application/json" -d "{\"text\": \"$message\"}" "$teams_channel"
}

# Main script:
if systemctl is-active --quiet proxysql; then
  # ProxySQL running, exiting.
  echo "ProxySQL is active, exiting"
  exit 0

else
  # ProxySQL not running, notify service alerts channel.
  teams_notification
  echo "ProxySQL is inactive, exiting"
  exit 1
fi
