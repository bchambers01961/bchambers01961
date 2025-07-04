#!/bin/bash
# Logfile location
logfile="myloader_log.txt"
# List of directories
directories=(
    "/data/registry_move/inc_reg_migration/10.200.10.195"
    "/data/registry_move/inc_reg_migration/46.175.48.29"
    "/data/registry_move/inc_reg_migration/77.86.34.29"
    "/data/registry_move/inc_reg_migration/10.100.23.101"
    "/data/registry_move/inc_reg_migration/10.100.10.190"
    "/data/registry_move/inc_reg_migration/10.200.10.191"
    "/data/registry_move/inc_reg_migration/10.100.10.191"
    "/data/registry_move/inc_reg_migration/46.175.48.124"
    "/data/registry_move/inc_reg_migration/46.175.48.101"
    "/data/registry_move/inc_reg_migration/46.175.48.55"
    "/data/registry_move/inc_reg_migration/46.175.48.173"
    "/data/registry_move/inc_reg_migration/77.86.34.126"
    "/data/registry_move/inc_reg_migration/77.86.34.124"
    "/data/registry_move/inc_reg_migration/46.175.48.126"
    "/data/registry_move/inc_reg_migration/10.100.10.196"
    "/data/registry_move/inc_reg_migration/77.86.34.101"
    "/data/registry_move/inc_reg_migration/10.200.10.196"
    "/data/registry_move/inc_reg_migration/77.86.34.173"
    "/data/registry_move/inc_reg_migration/77.86.34.55"
    "/data/registry_move/inc_reg_migration/10.200.10.190"
)

# Loop through each directory and run the myloader command
for dir in "${directories[@]}"; do
    myloader --host 127.0.0.1 \
    --defaults-file=.mydumper \
    --directory="$dir" \
    --database=message_orig \
    --queries-per-transaction=50000 \
    --threads=4 \
    --compress-protocol \
    --verbose=3 >> "$logfile" 2>&1
done
