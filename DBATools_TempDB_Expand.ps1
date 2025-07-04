# SCRIPT: DBATools_TempDB_Expand.ps1
# AUTHOR: Ben Chambers
# DATE: May 2025
# VERSION: 1.00
# PLATFORM: Windows Powershell
# PURPOSE: This script automates the process of setting TempDB to best practice configuration using DBATools.

# PREREQUISITES: 
# 1: DBATools must be installed on the machine this is being run on.
# 2: If moving directory, filepath must exist and SQL Service Account must have access.
# 3: If moving directory, new directory must be big enough to hold tempdb.
# 4: Script should be run without -ApplyChanges first. This will run it with WhatIf. The output should be analyzed.
# 5: .mdf files will be distributed based on number of cores. Each .mdf should be at least 8GB. If the WhatIf doesn't give this, consider a bigger drive.

# COMMON CUSTOM DENOMINATIONS:
# 1: 8GB = 8192MB

# Example commands
# 1: Changing existing tempdb drive to best practice config.
# C:\> .\TestingScript.ps1
# 2: Changing tempdb data and log files to separate drives, then setting up tempdb to best practice config.
#C:\> .\TestingScript.ps1 -ChangeTempDbDataPath "D:\SQL\TempDB\" -ChangeTempDbLogPath "C:\SQL\TempDB\" -ApplyChanges
# 3: Changing tempdb data and logfiles to the same drives, then setting up tempdb to best practice config.
#C:\> .\TestingScript.ps1 -ChangeTempDbDataPath "D:\SQL\TempDB\"
# 4: Command with -ApplyChanges flag, only with this flag will the command commit any changes.
#C:\> .\TestingScript.ps1 -ChangeTempDbDataPath "D:\SQL\TempDB\" -ChangeTempDbLogPath "D:\SQL\TempDB\" -ApplyChanges


#============================================================================================================
param(
    [string[]]$servers,
    [string]$ChangeTempDbDataPath = "",
    [string]$ChangeTempDbLogPath = "",
    [int]$CustomAmountMb = "",
    #[switch]$Use8GB_Per_Core,
    [switch]$DisableGrowth,
    [switch]$ApplyChanges
)
$logfile = "C:\Scripts\Logs\DBATools_TempDB_Expand.txt"
New-Item -Path $logfile -ItemType File -Force

Write-Host "ChangeTempDbDataPath: '$ChangeTempDbDataPath'"
Write-Host "ChangeTempDbLogPath: '$ChangeTempDbLogPath'"

# Set servers to be looped through.
#$servers = @("BenCTestVM\BEN_SQL_TEST")

foreach ($server in $servers) {
    if ($server -match '^\w+\\\w+') {
        Write-Host "$server is in server\instance format"
        $instance = $server.Substring($server.IndexOf('\') + 1)
        $server = $server.Substring(0, $server.IndexOf('\'))
        Write-Host "$instance is the instance"
        Write-Host "$server is the machine name"
        $SqlInstance = "$server\$instance"
        $ComputerName = $server
    } else {
        Write-Host "$server is both the server and instance name"
        $SqlInstance = "$server"
        $ComputerName = $server
    }

    function Optimize-TempDB {
        param (
            [string]$DataPath,
            [string]$LogPath,
            [int]$CustomMB
        )

        Set-DbatoolsInsecureConnection -SessionOnly

        $query = @"
        SELECT DISTINCT 
            LEFT(physical_name, 1) AS DriveLetter
        FROM sys.master_files
        WHERE database_id = DB_ID('tempdb')
		AND type_desc = 'ROWS';
"@

        $currenttempdbsizequery = @"
        SELECT 
            TotalSizeMB = CONVERT(NUMERIC(10,2), ROUND(SUM(size) / 128.0, 2))
        FROM sysfiles;
"@
        $cpu_count = @"
        SELECT
            cpu_count
        FROM sys.dm_os_sys_info;
"@

        $current_temp_db_size_result = Invoke-DbaQuery -SqlInstance "$SqlInstance" -Database tempdb -Query $currenttempdbsizequery
        $current_temp_db_size_mb = [double]$current_temp_db_size_result.TotalSizeMB

        # This part is only used if 8gb option is used.
        $current_cpu_count = Invoke-DbaQuery -SqlInstance "$SqlInstance" -Database master -Query $cpu_count
        $cpu_cores = [double]$current_cpu_count.cpu_count

        if ($DataPath -and -not (Test-Path $DataPath)) {
            Write-Host "The specified data path '$DataPath' does not exist on $ComputerName. Aborting."
            return
        }
        if ($LogPath -and -not (Test-Path $LogPath)) {
            Write-Host "The specified log path '$LogPath' does not exist on $ComputerName. Aborting."
            return
        }

        Write-Host "DataPath before conditional: '$DataPath'"

        if ($DataPath) {
            $tempdb_target_drive = $DataPath.Substring(0, $DataPath.IndexOf(':') + 2)
            Write-Verbose "Drive for new tempdb data directory: $tempdb_target_drive"
        } else {
            $tempdrive = Invoke-DbaQuery -SqlInstance "$SqlInstance" -Database master -Query $query
            $tempdb_target_drive = $tempdrive.DriveLetter + ":\"
            Write-Host "Using current tempdb drive $tempdb_target_drive"
        }

        $diskinfo = Get-DbaDiskSpace -ComputerName "$ComputerName" | Where-Object { $_.Name -eq $tempdb_target_drive }

        if (-not $diskinfo) {
            Write-Host "Could not find disk info for drive $tempdb_target_drive on $ComputerName"
            return
        }

        $freeGB = [math]::Round($diskinfo.Free / 1GB, 2)

        Write-Host "Disk Info: $($diskinfo | Out-String)"
        Write-Host "Raw FreeGB: $freeGB"
        Write-Host "Type: $($freeGB.GetType().FullName)"
        Write-Host "Raw TempMB: $current_temp_db_size_mb"

        if (-not $CustomMB) {
            $new_tempdbsize_mb = [Math]::Floor($freeGB * 0.9 * 1024)
            Write-Host "$freeGB GB is total drive storage. $new_tempdbsize_mb MB is what will be split amongst tempdb."

            if (-not $DataPath) {
            $new_tempdbsize_mb = [Math]::Round($new_tempdbsize_mb + $current_temp_db_size_mb)
            Write-Host "$freeGB GB is total drive storage. $new_tempdbsize_mb MB should now have current tempdb added ($current_temp_db_size_mb)"
            }
        } else {
            $new_tempdbsize_mb = [Math]::Round($CustomMB * $cpu_cores)
            Write-Host "TempDb will be $CustomMB * the total cores ($cpu_cores) the total will be $new_tempdbsize_mb"
        }

        try {
            # Build the full parameter set including optional paths
            if ($DataPath -and $LogPath) {
                $SetTempDbParams = @{
                    Verbose       = $true
                    SqlInstance   = $SqlInstance
                    DataFileSize  = $new_tempdbsize_mb
                    DataPath      = $DataPath
                    LogPath       = $LogPath
                }
            } elseif ($DataPath) {
                $SetTempDbParams = @{
                    Verbose       = $true
                    SqlInstance   = $SqlInstance
                    DataFileSize  = $new_tempdbsize_mb
                    DataPath      = $DataPath
                    LogPath       = $DataPath
                }
            } else {
                $SetTempDbParams = @{
                    Verbose       = $true
                    SqlInstance   = $SqlInstance
                    DataFileSize  = $new_tempdbsize_mb
                }
            }
        
            if (-not $ApplyChanges) {
                $SetTempDbParams["WhatIf"] = $true
            }
            if ($DisableGrowth) {
                $SetTempDbParams["DisableGrowth"] = $true
            }
        
            Set-DbaTempDbConfig @SetTempDbParams *>> $logfile 
            if ($ApplyChanges) {
                # Restart SQL Service now changes are applied.
                Restart-DbaService -SqlInstance $SqlInstance -Force *>> $logfile
            }
        }
        
        catch {
            Write-Host "❌ Error occurred while running Set-DbaTempDbConfig"
            Write-Host "Error Message: $($_.Exception.Message)"
            Write-Host "Full Error: $($_ | Out-String)"
            Write-Host "Last Error in \{$Error}: $($Error[0] | Out-String)"
        }
        
    
    }

    try {
    Write-Host "Optimizing tempdb for $server"

    $Error.Clear()
    $ErrorActionPreference = "Stop"

    Optimize-TempDB -DataPath $ChangeTempDbDataPath -LogPath $ChangeTempDbLogPath -CustomMB $CustomAmountMb
}
catch {
    Write-Host "❌ Failed to optimize tempdb for $server"
    Write-Host "Error Message: $($_.Exception.Message)"
    Write-Host "Full Error: $($_ | Out-String)"
    Write-Host "Stack Trace: $($_.ScriptStackTrace)"
}
finally {
    $ErrorActionPreference = "Continue"
}


}
