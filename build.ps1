$wc = [System.Net.WebClient]::new()
$sb = [System.Text.StringBuilder]::new()

[void]$sb.AppendLine("use master;")
[void]$sb.AppendLine("go")
[void]$sb.AppendLine()

#tables
$tbl_waitStats = ".\Setup\WaitStats.sql"
$tbl_whoIsActive = ".\Setup\WhoIsActive.sql"
$tbl_commandLog = "https://raw.githubusercontent.com/olahallengren/sql-server-maintenance-solution/master/CommandLog.sql"

[void]$sb.AppendLine((Get-Content $tbl_waitStats | Out-String))
[void]$sb.AppendLine((Get-Content $tbl_whoIsActive | Out-String))
[void]$sb.AppendLine($wc.DownloadString($tbl_commandLog))

#sprocs
$sp_whoIsActive = ".\Setup\sp_whoIsActive.sql"
$sp_commandExecute = "https://raw.githubusercontent.com/olahallengren/sql-server-maintenance-solution/master/CommandExecute.sql"
$sp_databaseIntegrityCheck = "https://raw.githubusercontent.com/olahallengren/sql-server-maintenance-solution/master/DatabaseIntegrityCheck.sql"
$sp_indexOptimize = "https://raw.githubusercontent.com/olahallengren/sql-server-maintenance-solution/master/IndexOptimize.sql"
$sp_Blitz = "https://raw.githubusercontent.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/dev/sp_Blitz.sql"
$sp_BlitzCache = "https://raw.githubusercontent.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/dev/sp_BlitzCache.sql"
$sp_BlitzIndex = "https://raw.githubusercontent.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/dev/sp_BlitzIndex.sql"
$sp_EasyButton = "https://raw.githubusercontent.com/pimbrouwers/sp_EasyButton/master/sp_EasyButton.sql"
$sp_CaptureWaitStats = ".\Setup\sp_CaptureWaitStats.sql"

[void]$sb.AppendLine((Get-Content $sp_whoIsActive | Out-String))
[void]$sb.AppendLine($wc.DownloadString($sp_commandExecute))
[void]$sb.AppendLine($wc.DownloadString($sp_databaseIntegrityCheck))
[void]$sb.AppendLine($wc.DownloadString($sp_indexOptimize))
[void]$sb.AppendLine($wc.DownloadString($sp_Blitz))
[void]$sb.AppendLine($wc.DownloadString($sp_BlitzCache))
[void]$sb.AppendLine($wc.DownloadString($sp_BlitzIndex))
[void]$sb.AppendLine($wc.DownloadString($sp_EasyButton))
[void]$sb.AppendLine((Get-Content $sp_CaptureWaitStats | Out-String))

#jobs
[void]$sb.AppendLine("use msdb;")
[void]$sb.AppendLine("go")
[void]$sb.AppendLine()

$job_checkDb = ".\Setup\Jobs\CheckDb.sql"
$job_whoIsActive = ".\Setup\Jobs\WhoIsActive.sql"
$job_waitStats = ".\Setup\Jobs\WaitStats.sql"
$job_statistics = ".\Setup\Jobs\Statistics.sql"
$job_cycleLogs = ".\Setup\Jobs\CycleLogs.sql"
$job_rebuildIndexes = ".\Setup\Jobs\RebuildIndexes.sql"

[void]$sb.AppendLine((Get-Content $job_checkDb | Out-String))
[void]$sb.AppendLine((Get-Content $job_whoIsActive | Out-String))
[void]$sb.AppendLine((Get-Content $job_waitStats | Out-String))
[void]$sb.AppendLine((Get-Content $job_statistics | Out-String))
[void]$sb.AppendLine((Get-Content $job_cycleLogs | Out-String))
[void]$sb.AppendLine((Get-Content $job_rebuildIndexes | Out-String))

Set-Content -Path .\install.sql -Value $sb.ToString()