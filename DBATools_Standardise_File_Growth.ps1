# SCRIPT: DBATools_Standardise_File_Growth.ps1
# AUTHOR: Ben Chambers
# DATE: July 2025
# VERSION: 1.00
# PLATFORM: Windows Powershell
# PURPOSE: This script goes through each DB and sets all user db's to pre configured best practice autogrow settings
# because every workload is different these can also be adjusted.

# USAGE:
# 1: Run script ensuring $servers variable is populated.
# 2: For custom growth sizes these can be changed. If not leave as default.
# 3: Run with -ApplyChanges to run without -WhatIf
#===========================================================================================================
param(
    [string[]]$servers,
    [int]$DataGrowthMB = 1024,
    [int]$LogGrowthMB = 512,
    [switch]$ApplyChanges,
    [switch]$CheckCurrent
)
$logfile = "C:\Scripts\Logs\DBATools_Standardise_File_Growth.txt"
$table_out = "C:\Scripts\Logs\DBATools_Standardise_File_Growth_Current.csv"

Write-Host "Running with the following variables:"
Write-Host "Servers: $servers"
Write-Host "DataGrowthMB: $DataGrowthMB"
Write-Host "LogGrowthMB: $LogGrowthMB"
Write-Host "ApplyChanges: $ApplyChanges"

#$servers = @("db34.csv", "db35.csv", "db36.csv", "db37.csv", "db38.csv", "db40.csv", "db41.csv", "db50.csv", "db51.csv", 
#"db52.csv", "db54.csv", "db57.csv", "db58.csv", "db59.csv", "db60.csv", "db61.csv", "db62.csv", "db63.csv", 
#"db64.csv", "db68.csv", "db72.csv", "db75.csv", "dbtest02.csv", "dbuk02.csv")
#$servers = @("BenCTestVM\BEN_SQL_TEST")

# Query to get user databases
$dblist_query = @"
SELECT db.name
FROM   master.sys.databases db
WHERE  
    db.state_desc = 'ONLINE' AND
    db.is_read_only = 0 AND
    db.name NOT IN ('master', 'model', 'msdb', 'tempdb') AND
    db.is_distributor = 0;

"@

# Work through each server sequentially
foreach ($server in $servers) {
    # Allow DBA tools to trust server for the session.
    Set-DbatoolsInsecureConnection -SessionOnly

    # Generate list of user db's ready to cycle through.
    $dblist = Invoke-DbaQuery -SqlInstance $server -Database master -Query $dblist_query
    # Loop through list of generated db's sequentially.
    foreach ($dbRow in $dblist) {
        $db = $dbRow.name
        Write-Host "Processing DB: $db"
        $Common_Params = @{
            SqlInstance     = $server
            Database        = $db
            GrowthType      = "MB"
            Verbose         = $true

        }

        $Check_Params = @{
            SqlInstance     = $server
            Database        = $db
            Verbose         = $true
        }
        if (-not $ApplyChanges) {
                $Common_Params["WhatIf"] = $true
            }
        try {
            # Check current settings instead if flag is set.
            if ($CheckCurrent) {
                # Check current settings and output to CSV
                Get-DbaDbFileGrowth @Check_Params | 
                Select-Object ComputerName, InstanceName, SqlInstance, Database, MaxSize, GrowthType, Growth, File, FileName, State |
                Export-Csv -Path $table_out -NoTypeInformation -Append -Force
            } else {
                # Set Data File to new value.
                Set-DbaDbFileGrowth @Common_Params -Growth $DataGrowthMB -FileType DATA *>> $logfile
                # Set Log File to new value.
                Set-DbaDbFileGrowth @Common_Params -Growth $LogGrowthMB -FileType LOG *>> $logfile
                Write-Host "Processing DB: $db complete, Datafile growth set to '$DataGrowthMB'MB and Logfile growth set to '$LogGrowthMB'MB." >> $logfile
            }
            
            
        } catch {
            if ($CheckCurrent) {
                Write-Host "❌ Error occurred while running Get-DbaDbFileGrowth" >> $logfile
            } else {
                Write-Host "❌ Error occurred while running Set-DbaDbFileGrowth" >> $logfile
            }
            Write-Host "Error Message: $($_.Exception.Message)" >> $logfile
            Write-Host "Full Error: $($_ | Out-String)" >> $logfile
            Write-Host "Last Error in \{$Error}: $($Error[0] | Out-String)" >> $logfile
        }
        
    }

}
