#install.sql
if (Test-Path .\install.sql){
    Remove-Item .\install.sql
}

Get-Content -Path .\Setup\*.sql| Add-Content .\install.sql

#install-jobs.sql
if (Test-Path .\install-jobs.sql){
    Remove-Item .\install-jobs.sql
}

Get-Content -Path .\Jobs\*.sql | Add-Content .\install-jobs.sql