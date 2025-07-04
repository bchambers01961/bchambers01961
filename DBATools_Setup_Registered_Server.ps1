$servers = @("db34", "db35", "db36", "db37", "db38", "db39", "db40", "db41", "db42", "db43", "db44", "db45", "db46", "db48", "db49", "db50", 
"db51", "db52", "db53", "db54", "db55", "db56", "db57", "db58", "db59", "db60", "db61", "db62", "db63", "db64", "db65", "db66", 
"db67", "db68", "db69", "db71", "db72", "db73", "db74", "db75", "dbtest02", "dbuk02")
$outputdir = "C:\Temp\"
$query=@'
SELECT
	@@SERVERNAME AS server_name,
	db.name,
	db.database_id,
	db.state_desc,
	db.compatibility_level,
	db.recovery_model_desc,
	db.snapshot_isolation_state_desc,
	db.is_read_committed_snapshot_on,
	db.is_read_only
FROM sys.databases AS db
WHERE db.recovery_model_desc = 'FULL'
AND db.name NOT IN ('master','model','msdb');
'@

for ($i = 0; $i -lt $servers.Length; $i++) {
    $server = $servers[$i]
    Write-Host "Processing server: $server"
    try{
    # DBA Tools Batched Task
    Set-DbatoolsInsecureConnection -SessionOnly
	$result = Invoke-DbaQuery -SqlInstance $server -Database master -Query $query
    if ($result) {
        $result | Export-Csv -Path "$outputdir\serverlist.csv" -NoTypeInformation -Append
        Write-Host "Query executed successfully on $server and results saved."
    } else {
        Write-Host "Query executed on $server but returned no results."
    }

    } catch {
        $errorMessage = "Error running query on $server $_"
        Write-Host $errorMessage
        Add-Content -Path "$outputdir\log.txt" -Value $errorMessage
    }
}
