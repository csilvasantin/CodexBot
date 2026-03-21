# ============================================================
#  CodexBot Watcher — starts/stops CodexBot with Codex app
# ============================================================

param(
    [int]$Interval = 5
)

$botScript = Join-Path $PSScriptRoot "CodexBot.ps1"

function Find-CodexWindow {
    $proc = Get-Process -Name "Codex" -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
        Select-Object -First 1
    if ($proc) { return $proc }
    Get-Process | Where-Object {
        $_.MainWindowTitle -like "*Codex*" -and $_.MainWindowHandle -ne [IntPtr]::Zero
    } | Select-Object -First 1
}

function Get-BotProcess {
    Get-Process pwsh -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*CodexBot.ps1*" }
}

function Start-Bot {
    if (Get-BotProcess) { return }
    Start-Process conhost.exe -ArgumentList "pwsh -File `"$botScript`""
    Write-Host "[Watcher] Codex detected -> CodexBot launched" -ForegroundColor Green
}

function Stop-Bot {
    $procs = Get-BotProcess
    if (-not $procs) { return }
    $procs | Stop-Process -Force
    Write-Host "[Watcher] Codex closed -> CodexBot stopped" -ForegroundColor Yellow
}

Write-Host "CodexBot Watcher running. Press q to stop." -ForegroundColor Cyan

while ($true) {
    try {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q') {
                Stop-Bot
                break
            }
        }
    } catch {}

    if (Find-CodexWindow) {
        Start-Bot
    } else {
        Stop-Bot
    }

    Start-Sleep -Seconds $Interval
}

Write-Host "CodexBot Watcher finished." -ForegroundColor Cyan
