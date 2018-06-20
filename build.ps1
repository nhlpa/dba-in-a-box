if (Test-Path .\install.sql){
    Remove-Item .\install.sql
}

Get-Content -Path .\Setup\*.sql| Add-Content .\install.sql
