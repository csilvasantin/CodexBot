# Launch CodexBot in its own window — kills previous instances first
$script = Join-Path $PSScriptRoot "CodexBot.ps1"
Get-Process pwsh -EA 0 | Where-Object { $_.CommandLine -like "*CodexBot*" -and $_.Id -ne $PID } | Stop-Process -Force
Start-Process conhost.exe -ArgumentList "pwsh -File `"$script`""
Write-Host "CodexBot launched!" -ForegroundColor Green
