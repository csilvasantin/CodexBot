# Launch CodexBot in its own window
# Usage: .\Launch.ps1
#        .\Launch.ps1 -Duration 60 -Interval 5

param(
    [int]$Duration = 30,
    [int]$Interval = 8,
    [switch]$AnyScreen,
    [switch]$Debug
)

$scriptPath = Join-Path $PSScriptRoot "CodexBot.ps1"
$args_str = "-File `"$scriptPath`" -Duration $Duration -Interval $Interval"
if ($AnyScreen) { $args_str += " -AnyScreen" }
if ($Debug) { $args_str += " -Debug" }

# Kill previous instances
Get-Process pwsh -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*CodexBot*" -and $_.Id -ne $PID } |
    ForEach-Object {
        Write-Host "Stopping previous CodexBot (PID $($_.Id))..." -ForegroundColor Yellow
        Stop-Process -Id $_.Id -Force
    }

# Launch in a new conhost window (independent handle for positioning)
Start-Process conhost.exe -ArgumentList "pwsh $args_str"
Write-Host "CodexBot launched! Check the new window." -ForegroundColor Green
