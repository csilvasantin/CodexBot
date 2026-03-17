# ============================================================
#  CodexBot v2.0 — Auto-approve Codex permission prompts
# ============================================================
#  Detects the green "En espera de aprobacion" badge in the
#  Codex sidebar and sends "2" to auto-approve.
#
#  Usage:
#    pwsh -File CodexBot.ps1                 # defaults (30m, 6s)
#    pwsh -File CodexBot.ps1 -Duration 60    # run 60 minutes
#    pwsh -File CodexBot.ps1 -Interval 4     # check every 4s
#
#  Stop: press 'q' or close the window
# ============================================================

param(
    [int]$Duration = 30,
    [int]$Interval = 6,
    [switch]$NoSave
)

# ---- Win32 API ----
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ([System.Management.Automation.PSTypeName]'CodexBot.Win32').Type) {
    Add-Type -Name Win32 -Namespace CodexBot -PassThru -MemberDefinition @"
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int Left, Top, Right, Bottom; }
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
        [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
"@ | Out-Null
}

$w32 = [CodexBot.Win32]

# ---- Config ----
$deadline = (Get-Date).AddMinutes($Duration)
$screenshotDir = Join-Path $PSScriptRoot "screenshots"
if (-not (Test-Path $screenshotDir)) { New-Item -ItemType Directory -Path $screenshotDir | Out-Null }

$totalChecks = 0
$totalApproved = 0
$startTime = Get-Date

# ---- Functions ----

function Find-CodexWindow {
    $proc = Get-Process -Name "Codex" -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
        Select-Object -First 1
    if ($proc) { return $proc }
    Get-Process | Where-Object {
        $_.MainWindowTitle -like "*Codex*" -and $_.MainWindowHandle -ne [IntPtr]::Zero
    } | Select-Object -First 1
}

function Get-WindowBitmap([IntPtr]$hwnd) {
    $rc = New-Object CodexBot.Win32+RECT
    $w32::GetWindowRect($hwnd, [ref]$rc) | Out-Null
    $w = $rc.Right - $rc.Left
    $h = $rc.Bottom - $rc.Top
    if ($w -le 0 -or $h -le 0) { return $null }
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $gfx.GetHdc()
    $w32::PrintWindow($hwnd, $hdc, 2) | Out-Null
    $gfx.ReleaseHdc($hdc)
    $gfx.Dispose()
    return $bmp
}

function Test-HasApprovalBadge([System.Drawing.Bitmap]$bmp) {
    # =============================================================
    # DETECTION: Green "En espera de aprobacion" badge in sidebar
    #
    # The Codex sidebar (x:0 to ~380px) shows a green badge when
    # there's a pending permission prompt. This badge has bright
    # green pixels (G > 140, R < 200, B < 120, G-R > 20).
    #
    # When no prompt: 0 green pixels in sidebar
    # When prompt:    500+ green pixels in sidebar badge area
    # Threshold:      100 green pixels = prompt detected
    # =============================================================

    if (-not $bmp) { return $false }
    $w = $bmp.Width; $h = $bmp.Height
    if ($w -lt 200 -or $h -lt 200) { return $false }

    # Scan sidebar area (x: 0-400, y: 150-500 where the badge appears)
    $sidebarW = [math]::Min(400, [math]::Floor($w * 0.35))
    $scanYStart = 150
    $scanYEnd = [math]::Min(500, [math]::Floor($h * 0.4))

    $greenPixels = 0
    for ($y = $scanYStart; $y -lt $scanYEnd; $y += 1) {
        for ($x = 0; $x -lt $sidebarW; $x += 2) {
            $px = $bmp.GetPixel($x, $y)
            # Green badge: G channel dominant
            if ($px.G -gt 140 -and $px.R -lt 200 -and $px.B -lt 120 -and ($px.G - $px.R) -gt 20) {
                $greenPixels++
            }
        }
    }

    $script:lastGreenCount = $greenPixels
    return $greenPixels -gt 100
}

function Send-Approval([IntPtr]$hwnd) {
    $cursorBefore = [System.Windows.Forms.Cursor]::Position
    $prevWindow = $w32::GetForegroundWindow()

    $w32::ShowWindow($hwnd, 9) | Out-Null
    Start-Sleep -Milliseconds 150
    $w32::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 300

    # Send "2" = approve and don't ask again
    [System.Windows.Forms.SendKeys]::SendWait("2")
    Start-Sleep -Milliseconds 200

    # Restore previous focus
    if ($prevWindow -ne [IntPtr]::Zero) {
        Start-Sleep -Milliseconds 100
        $w32::SetForegroundWindow($prevWindow) | Out-Null
    }
    [System.Windows.Forms.Cursor]::Position = $cursorBefore
}

function Write-Status($msg, $color = "Gray", $detail = "") {
    $remaining = [math]::Round(($deadline - (Get-Date)).TotalMinutes, 1)
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host "[$ts] " -NoNewline -ForegroundColor DarkGray
    Write-Host "$msg " -NoNewline -ForegroundColor $color
    if ($detail) { Write-Host "$detail " -NoNewline -ForegroundColor DarkGray }
    Write-Host "(${remaining}m | x${totalApproved})" -ForegroundColor DarkGray
}

# ---- Banner ----
Write-Host @"

   ____          _           ____        _
  / ___|___   __| | _____  _| __ )  ___ | |_
 | |   / _ \ / _`` |/ _ \ \/ /  _ \ / _ \| __|
 | |__| (_) | (_| |  __/>  <| |_) | (_) | |_
  \____\___/ \__,_|\___/_/\_\____/ \___/ \__|  v2.0

"@ -ForegroundColor Cyan

Write-Host "  Detects green 'En espera de aprobacion' badge in sidebar" -ForegroundColor White
Write-Host "  Duration: ${Duration}m  |  Interval: ${Interval}s  |  Press 'q' to stop" -ForegroundColor Gray
Write-Host "  ────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# ---- Main Loop ----
while ((Get-Date) -lt $deadline) {
    try {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q') {
                Write-Status "Stopped by user." "Yellow"; break
            }
        }
    } catch {}

    $totalChecks++
    $script:lastGreenCount = 0

    $proc = Find-CodexWindow
    if (-not $proc) {
        Write-Status "Codex not found..." "DarkYellow"
        Start-Sleep -Seconds $Interval; continue
    }

    $hwnd = $proc.MainWindowHandle
    if ($w32::IsIconic($hwnd)) {
        $w32::ShowWindow($hwnd, 4) | Out-Null
        Start-Sleep -Milliseconds 300
    }

    $bmp = $null
    $isPrompt = $false
    try {
        $bmp = Get-WindowBitmap $hwnd
        if ($bmp) {
            if (-not $NoSave) {
                $bmp.Save("$screenshotDir\codex_last.png", [System.Drawing.Imaging.ImageFormat]::Png)
            }
            $isPrompt = Test-HasApprovalBadge $bmp
            $bmp.Dispose(); $bmp = $null
        }
    } catch {
        if ($bmp) { $bmp.Dispose() }
        Write-Status "Error: $_" "Red"
    }

    if ($isPrompt) {
        # Save evidence screenshot before approving
        if (-not $NoSave) {
            $ts = Get-Date -Format 'HHmmss'
            Copy-Item "$screenshotDir\codex_last.png" "$screenshotDir\prompt_$ts.png" -ErrorAction SilentlyContinue
        }

        Send-Approval $hwnd
        $totalApproved++
        Write-Status "APPROVED!" "Green" "[green:$($script:lastGreenCount)px]"

        # Wait extra time after approval for Codex to process
        Start-Sleep -Seconds 3
    } else {
        Write-Status "No prompt" "DarkCyan" "[green:$($script:lastGreenCount)px]"
    }

    # Wait with quit check
    for ($i = 0; $i -lt $Interval; $i++) {
        try {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q') {
                    Write-Status "Stopped." "Yellow"; $deadline = Get-Date; break
                }
            }
        } catch {}
        Start-Sleep -Seconds 1
    }
}

# ---- Summary ----
$elapsed = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
Write-Host "`n  ────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  Runtime: ${elapsed}m | Checks: $totalChecks | Approved: $totalApproved" -ForegroundColor $(if ($totalApproved -gt 0) {"Green"} else {"Gray"})
Write-Host "  CodexBot finished.`n" -ForegroundColor Cyan
