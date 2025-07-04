# sync-to-onedrive.ps1

# Bash Scripts
$sourceBash = "C:\Scripts\Bash-Scripts"
$destBash = "C:\Users\Ben.Chambers\OneDrive - Giacom World Networks Ltd\Infrastructure\Database Admin\MySQL\Bash-Scripts"

# PowerShell Scripts
$sourcePS = "C:\Scripts\PowerShell-Scripts"
$destPS = "C:\Users\Ben.Chambers\OneDrive - Giacom World Networks Ltd\Infrastructure\Database Admin\MSSQL\Powershell-Scripts"

# Mirror the folders
robocopy $sourceBash $destBash /MIR /XD ".git"
robocopy $sourcePS $destPS /MIR /XD ".git"
