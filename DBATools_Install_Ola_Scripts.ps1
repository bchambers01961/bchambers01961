$servers = @("db34", "db35", "db36", "db37", "db38", "db39", "db40", "db41", "db42", "db43", "db44", "db45", "db46", "db48", "db49", "db50", 
"db51", "db52", "db53", "db54", "db55", "db56", "db57", "db58", "db59", "db60", "db61", "db62", "db63", "db64", "db65", "db66", 
"db67", "db68", "db69", "db71", "db72", "db73", "db74", "db75", "dbtest02", "dbuk02")

foreach ($server in $servers) {
    Set-DbatoolsInsecureConnection -SessionOnly
Install-DbaMaintenanceSolution -SqlInstance $server -Database DBA_Maintenance -InstallJobs -CleanupTime $backup_retention_hours
        Write-Output "$server is what the script sees."
}
