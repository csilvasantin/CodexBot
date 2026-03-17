# ============================================================
#  CodexBot v1.2 — Auto-approve Codex permission prompts
# ============================================================
#  Monitors the Codex desktop app and automatically sends "2"
#  (Yes, don't ask again) whenever it detects a permission prompt.
#
#  Codex desktop app has a LIGHT theme (white background).
#  Detection: compares consecutive screenshots to detect when UI
#  stops streaming (stable) and then checks for prompt patterns.
#
#  Usage:
#    pwsh -File CodexBot.ps1                    # defaults
#    pwsh -File CodexBot.ps1 -Duration 60       # run 60 minutes
#    pwsh -File CodexBot.ps1 -Interval 5        # check every 5s
#
#  Stop: press 'q' or close the window
# ============================================================

param(
    [int]$Duration = 30,
    [int]$Interval = 6,
    [switch]$LeftScreenOnly,
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
$prevHash = ""
$stableCount = 0

# ---- Functions ----

function Find-CodexWindow {
    $proc = Get-Process -Name "Codex" -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
        Select-Object -First 1
    if ($proc) { return $proc }
    $proc = Get-Process | Where-Object {
        $_.MainWindowTitle -like "*Codex*" -and $_.MainWindowHandle -ne [IntPtr]::Zero
    } | Select-Object -First 1
    return $proc
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

function Get-BitmapHash([System.Drawing.Bitmap]$bmp) {
    # Quick hash of bottom 300px to detect changes
    if (-not $bmp) { return "" }
    $w = $bmp.Width; $h = $bmp.Height
    $sb = [System.Text.StringBuilder]::new()
    $startY = [math]::Max(0, $h - 300)
    for ($y = $startY; $y -lt $h; $y += 15) {
        for ($x = 10; $x -lt $w; $x += [math]::Max(1, [math]::Floor($w / 20))) {
            $px = $bmp.GetPixel($x, $y)
            $sb.Append([math]::Floor($px.R / 16)) | Out-Null
            $sb.Append([math]::Floor($px.G / 16)) | Out-Null
            $sb.Append([math]::Floor($px.B / 16)) | Out-Null
        }
    }
    return $sb.ToString()
}

function Test-IsPermissionPrompt([System.Drawing.Bitmap]$bmp) {
    # Codex DESKTOP APP — light theme, white background
    # When idle: text input box at bottom
    # When prompt: colored buttons/options, dark bands, accent colors
    #
    # Signals detected in bottom 300px:
    # A) Blue accent (buttons/links)
    # B) Green accent (approve buttons)
    # C) Dark horizontal bands (option containers)
    # D) Orange/yellow warnings

    if (-not $bmp) { return $false }
    $w = $bmp.Width; $h = $bmp.Height
    if ($w -lt 100 -or $h -lt 100) { return $false }

    $scanStart = [math]::Max(0, $h - 300)

    # Signal A: Blue accents
    $blueAccent = 0
    for ($y = $scanStart; $y -lt $h; $y += 2) {
        for ($x = 10; $x -lt ($w - 10); $x += 3) {
            $px = $bmp.GetPixel($x, $y)
            if ($px.B -gt 150 -and $px.R -lt 100 -and $px.G -lt 160) {
                $blueAccent++
            }
        }
    }

    # Signal B: Green accents
    $greenAccent = 0
    for ($y = $scanStart; $y -lt $h; $y += 2) {
        for ($x = 10; $x -lt ($w - 10); $x += 3) {
            $px = $bmp.GetPixel($x, $y)
            if ($px.G -gt 130 -and $px.R -lt 80 -and $px.B -lt 100) {
                $greenAccent++
            }
        }
    }

    # Signal C: Dark bands
    $darkBandRows = 0
    for ($y = $scanStart; $y -lt $h; $y += 4) {
        $darkInRow = 0
        $total = 0
        for ($x = 50; $x -lt ($w - 50); $x += 5) {
            $px = $bmp.GetPixel($x, $y)
            $total++
            if ($px.R -lt 60 -and $px.G -lt 60 -and $px.B -lt 60) {
                $darkInRow++
            }
        }
        if ($total -gt 0 -and $darkInRow -gt ($total * 0.3)) {
            $darkBandRows++
        }
    }

    # Signal D: Warning/orange
    $warningAccent = 0
    for ($y = $scanStart; $y -lt $h; $y += 3) {
        for ($x = 10; $x -lt [math]::Min(500, $w); $x += 3) {
            $px = $bmp.GetPixel($x, $y)
            if ($px.R -gt 200 -and $px.G -gt 120 -and $px.G -lt 200 -and $px.B -lt 60) {
                $warningAccent++
            }
        }
    }

    $script:lastSignals = "B:$blueAccent G:$greenAccent D:$darkBandRows W:$warningAccent"

    $hasBlue = $blueAccent -gt 20
    $hasGreen = $greenAccent -gt 15
    $hasDark = $darkBandRows -gt 3
    $hasWarn = $warningAccent -gt 5

    $signalCount = @($hasBlue, $hasGreen, $hasDark, $hasWarn).Where({ $_ }).Count
    if ($signalCount -ge 2) { return $true }
    if ($hasDark -and $darkBandRows -gt 6) { return $true }

    return $false
}

function Send-Approval([IntPtr]$hwnd) {
    $cursorBefore = [System.Windows.Forms.Cursor]::Position
    $prevWindow = $w32::GetForegroundWindow()

    $w32::ShowWindow($hwnd, 9) | Out-Null
    Start-Sleep -Milliseconds 150
    $w32::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 300

    [System.Windows.Forms.SendKeys]::SendWait("2")
    Start-Sleep -Milliseconds 200

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
  \____\___/ \__,_|\___/_/\_\____/ \___/ \__|  v1.2

"@ -ForegroundColor Cyan

Write-Host "  Duration: ${Duration}m  |  Interval: ${Interval}s  |  Press 'q' to stop" -ForegroundColor Gray
Write-Host "  Screenshots: $screenshotDir" -ForegroundColor DarkGray
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
    $script:lastSignals = ""

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
            $hash = Get-BitmapHash $bmp
            if ($hash -eq $prevHash) { $stableCount++ } else { $stableCount = 0; $prevHash = $hash }

            if (-not $NoSave) {
                $bmp.Save("$screenshotDir\codex_last.png", [System.Drawing.Imaging.ImageFormat]::Png)
                $ts = Get-Date -Format 'HHmmss'
                $bmp.Save("$screenshotDir\codex_$ts.png", [System.Drawing.Imaging.ImageFormat]::Png)
                $old = Get-ChildItem $screenshotDir -Filter "codex_[0-9]*.png" | Sort-Object LastWriteTime | Select-Object -SkipLast 15
                foreach ($f in $old) { Remove-Item $f.FullName -Force }
            }

            # Only check for prompt if UI is stable (not actively streaming)
            if ($stableCount -ge 1) {
                $isPrompt = Test-IsPermissionPrompt $bmp
            }

            $bmp.Dispose(); $bmp = $null
        }
    } catch {
        if ($bmp) { $bmp.Dispose() }
        Write-Status "Error: $_" "Red"
    }

    if ($isPrompt) {
        Send-Approval $hwnd
        $totalApproved++
        $stableCount = 0; $prevHash = ""
        Write-Status "APPROVED!" "Green" "[$($script:lastSignals)]"
    } elseif ($stableCount -ge 1) {
        Write-Status "Stable" "DarkCyan" "[$($script:lastSignals)] s:$stableCount"
    } else {
        Write-Status "Streaming..." "DarkCyan"
    }

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

$elapsed = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
Write-Host "`n  ────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  Runtime: ${elapsed}m | Checks: $totalChecks | Approved: $totalApproved" -ForegroundColor $(if ($totalApproved -gt 0) {"Green"} else {"Gray"})
Write-Host "  CodexBot finished.`n" -ForegroundColor Cyan
