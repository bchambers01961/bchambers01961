$servers = @("db34", "db35", "db36", "db37", "db38", "db39", "db40", "db41", "db42", "db43", "db44", "db45", "db46", "db48", "db49", "db50", 
"db51", "db52", "db53", "db54", "db56", "db57", "db58", "db59", "db60", "db61", "db62", "db63", "db64", "db65", "db66", 
"db67", "db68", "db69", "db71", "db72", "db73", "db74", "db75", "dbtest02", "dbuk02")
# Backup retention set to 30 days as that is what is contractually retained for aBILLity.
$backup_retention_hours = 720

foreach ($server in $servers) {
    Set-DbatoolsInsecureConnection -SessionOnly
Install-DbaMaintenanceSolution -SqlInstance $server -Database DBA_Data -InstallJobs -CleanupTime $backup_retention_hours
        Write-Output "$server is what the script sees."
    # A better option is set each separate job up.
    # Leave backups out of this script as these will be their own challenge. Each server is backed up to URL so 
   #Install-DbaMaintenanceSolution -SqlInstance $server -Database DBA_Data -Solution Backup -ReplaceExisting -CleanupTime $backup_retention_hours

   Install-DbaMaintenanceSolution -SqlInstance $server -Database DBA_Data -Solution IntegrityCheck -LogToTable -ReplaceExisting 
   Install-DbaMaintenanceSolution -SqlInstance $server -Database DBA_Data -Solution IndexOptimize -LogToTable -ReplaceExisting


    # Create new schedule's
    $schedule_2am = New-DbaAgentSchedule -SqlInstance $server -Name "Daily 2AM" `
        -FrequencyType Daily -FrequencyInterval 1 -StartTime 020000

    $schedule_230am = New-DbaAgentSchedule -SqlInstance $server -Name "Daily 230AM" `
        -FrequencyType Daily -FrequencyInterval 1 -StartTime 023000

    $schedule_weekly_1am = New-DbaAgentSchedule -SqlInstance $server -Name "Weekly 1AM" `
        -FrequencyType Weekly -FrequencyInterval 1 -StartTime 010000

    # Attach the schedule to the job
    Set-DbaAgentJob -SqlInstance $server -Job "IndexOptimize - USER_DATABASES" -Schedule $schedule_weekly_1am
    Set-DbaAgentJob -SqlInstance $server -Job "DatabaseIntegrityCheck - SYSTEM_DATABASES" -Schedule $schedule_2am
    Set-DbaAgentJob -SqlInstance $server -Job "DatabaseIntegrityCheck - USER_DATABASES" -Schedule $schedule_230am
    
    # Create nightly update modified statistics job


}
