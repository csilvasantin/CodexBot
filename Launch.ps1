# Launch CodexBot Watcher in its own window — kills previous watcher first
$script = Join-Path $PSScriptRoot "CodexBot-Watcher.ps1"
Get-Process pwsh -EA 0 | Where-Object { $_.CommandLine -like "*CodexBot-Watcher*" -and $_.Id -ne $PID } | Stop-Process -Force
Start-Process conhost.exe -ArgumentList "pwsh -File `"$script`""
Write-Host "CodexBot watcher launched!" -ForegroundColor Green
