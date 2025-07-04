#!/bin/bash

logfile=/path/to/log


super_rsync(){
    # Set local variables $1 and $2, they need to be the full filepaths for the directories.
    local rsync_cpu_cores=$(lscpu | awk '/^CPU\(s\):/ {printf "%.0f\n", $2 * 0.8}');
    local source_dir=$1
    local dest_dir=$2

    #creates destination dir in case it doesn't exist
    mkdir -p "$dest_dir"
    date >> $logfile

    #cd to backupdir to prevent rsync from creating the full path in the destination
    cd $backupdir
    # Checks if parallel is installed, if not the script uses xargs.
    if command -v parallel > /dev/null; then
        echo "Using parallel for rsync" >> $logfile
        find $source_dir -mindepth 1 | parallel -j $rsync_cpu_cores rsync -avRP --relative {} $dest_dir >> $logfile 2>&1
    else
        echo "Parallel not found, using xargs for rsync" >> $logfile
        find $source_dir -mindepth 1 | xargs -n1 -P$rsync_cpu_cores -I% rsync -avRP --relative % $dest_dir >> $logfile 2>&1
    fi
    date >> $logfile

    return
}

#Calls the function
super_rsync /path/to/source /path/to/destination