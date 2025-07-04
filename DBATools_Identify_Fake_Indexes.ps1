# Servers to be looped through.
$servers = @("db50","db51","dbtest02","dbuk02")
#$servers = @("BenCTestVM\BEN_SQL_TEST")
$outputdir = "C:\Temp\"

# Query to get user databases
$dblist_query = @"
SELECT db.name
FROM   master.sys.databases db
WHERE  CAST(CASE WHEN name IN ('master', 'model', 'msdb', 'tempdb') THEN 1 ELSE is_distributor END AS bit) = 0;
"@

foreach ($server in $servers) {
    Write-Host "Processing server: $server"
    Set-DbatoolsInsecureConnection -SessionOnly

    $dblist = Invoke-DbaQuery -SqlInstance $server -Database master -Query $dblist_query

    foreach ($dbRow in $dblist) {
        $db = $dbRow.name
        Write-Host "Processing DB: $db"

        # Build the query dynamically with the current DB name
        $query = @"
USE [$db];

WITH hi AS (
    SELECT QUOTENAME(SCHEMA_NAME(o.[schema_id])) +'.'+ QUOTENAME(OBJECT_NAME(i.[object_id])) AS [Table],
           QUOTENAME([i].[name]) AS [Index_or_Statistics], 1 AS [Type]
    FROM sys.[indexes] AS [i]
    JOIN sys.[objects] AS [o] ON i.[object_id] = o.[object_id]
    WHERE INDEXPROPERTY(i.[object_id], i.[name], 'IsHypothetical') = 1
      AND OBJECTPROPERTY([o].[object_id], 'IsUserTable') = 1

    UNION ALL

    SELECT QUOTENAME(SCHEMA_NAME(o.[schema_id])) +'.'+ QUOTENAME(OBJECT_NAME(o.[object_id])) AS [Table],
           QUOTENAME([s].[name]) AS [Index_or_Statistics], 2 AS [Type]
    FROM sys.[stats] AS [s]
    JOIN sys.[objects] AS [o] ON [o].[object_id] = [s].[object_id]
    WHERE [s].[user_created] = 0
      AND [o].[name] LIKE '[_]dta[_]%'
      AND OBJECTPROPERTY([o].[object_id], 'IsUserTable') = 1
)
SELECT 
    @@servername AS servername,
    DB_NAME() AS dbname,
    [hi].[Table],
    [hi].[Index_or_Statistics],
    CASE [hi].[Type] 
        WHEN 1 THEN 'USE ' + DB_NAME() + '; DROP INDEX ' + [hi].[Index_or_Statistics] + ' ON ' + [hi].[Table] + ';'
        WHEN 2 THEN 'USE ' + DB_NAME() + '; DROP STATISTICS ' + hi.[Table] + '.' + hi.[Index_or_Statistics] + ';'
        ELSE 'UNKNOWN'
    END AS [T-SQL Drop Command]
FROM [hi];
"@

        try {
            $result = Invoke-DbaQuery -SqlInstance $server -Database $db -Query $query
            if ($result) {
                # Remove backslashes from sql instance if needed.
                $safeserver = $server -replace '\\','_'
                # Ensure output directory exists.
                if ( -not (Test-Path $outputdir)){
                    New-Item -Path $outputdir -ItemType Directory -Out-Null
                }

                # Build safe filepath and save alter statements to it.
                $csvPath = Join-Path $outputdir "$safeserver`_$db`_fake_indexes.csv"
                $result | Export-Csv -Path $csvPath -NoTypeInformation -Append
                Write-Host "Results saved to $csvPath"
            } else {
                # No .csv created if there aren't results
                Write-Host "No results for $db on $server"
            }
        } catch {
            $errorMessage = "Error running query on $server ($db): $_"
            Write-Host $errorMessage
            Add-Content -Path "$outputdir\log.txt" -Value $errorMessage
        }
    }
}
