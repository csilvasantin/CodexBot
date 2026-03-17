# ============================================================
#  CodexBot v1.0 — Auto-approve Codex permission prompts
# ============================================================
#  Monitors the Codex CLI window and automatically sends "2"
#  (Yes, don't ask again) whenever it detects a permission prompt.
#
#  Usage:
#    pwsh -File CodexBot.ps1                    # defaults
#    pwsh -File CodexBot.ps1 -Duration 10       # run 10 minutes
#    pwsh -File CodexBot.ps1 -Interval 10       # check every 10s
#    pwsh -File CodexBot.ps1 -AnyScreen          # don't restrict to left screen
#
#  Stop: press 'q' or close the window
# ============================================================

param(
    [int]$Duration = 30,        # minutes to run (default 30)
    [int]$Interval = 8,         # seconds between checks
    [switch]$AnyScreen,         # allow any screen, not just left
    [switch]$Debug              # save screenshots for debugging
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
        [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
"@ | Out-Null
}

$w32 = [CodexBot.Win32]

# ---- Configuration ----
$deadline = (Get-Date).AddMinutes($Duration)
$screenshotDir = Join-Path $PSScriptRoot "screenshots"
if ($Debug -and -not (Test-Path $screenshotDir)) {
    New-Item -ItemType Directory -Path $screenshotDir | Out-Null
}

# Left screen bounds (user's setup: vertical 1440x2560 at -1440,-215)
$leftScreenMinX = -1440
$leftScreenMaxX = 0

# Stats
$totalChecks = 0
$totalApproved = 0
$startTime = Get-Date

# ---- Functions ----

function Find-CodexWindow {
    # Search by multiple patterns to be more robust
    $patterns = @("*Codex*", "*codex*", "*CODEX*")
    foreach ($pattern in $patterns) {
        $proc = Get-Process | Where-Object {
            $_.MainWindowTitle -like $pattern -and $_.MainWindowHandle -ne [IntPtr]::Zero
        } | Select-Object -First 1
        if ($proc) { return $proc }
    }
    return $null
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
    $w32::PrintWindow($hwnd, $hdc, 2) | Out-Null   # PW_RENDERFULLCONTENT
    $gfx.ReleaseHdc($hdc)
    $gfx.Dispose()
    return $bmp
}

function Test-IsPermissionPrompt([System.Drawing.Bitmap]$bmp) {
    # Strategy: Codex permission prompts have numbered options (1, 2, 3) in the
    # bottom portion. The text input mode has a green "send" button circle.
    #
    # We use TWO signals:
    #   1. Absence of the green send button (bottom-right) = might be a prompt
    #   2. Presence of cyan/teal option numbers (bottom-left) = likely a prompt
    #
    # Both must agree to trigger approval.

    if (-not $bmp) { return $false }
    $w = $bmp.Width
    $h = $bmp.Height

    # --- Signal 1: Green send button (bottom-right quadrant, last 150px) ---
    $scanTop = [math]::Max(0, $h - 150)
    $scanLeftHalf = [math]::Floor($w / 2)
    $greenCount = 0
    for ($y = $scanTop; $y -lt $h; $y += 3) {
        for ($x = $scanLeftHalf; $x -lt $w; $x += 3) {
            $px = $bmp.GetPixel($x, $y)
            # Green send button: high G, low R, low-mid B
            if ($px.G -gt 110 -and $px.G -gt ($px.R * 1.5) -and $px.R -lt 100 -and $px.B -lt 120) {
                $greenCount++
            }
        }
    }
    $hasSendButton = $greenCount -gt 5

    # --- Signal 2: Cyan/teal option number text (bottom-left, last 200px) ---
    $cyanCount = 0
    $scanBottomStart = [math]::Max(0, $h - 200)
    for ($y = $scanBottomStart; $y -lt $h; $y += 3) {
        for ($x = 10; $x -lt [math]::Min(300, $w); $x += 3) {
            $px = $bmp.GetPixel($x, $y)
            # Cyan/teal option numbers: high G+B, low R
            if ($px.G -gt 140 -and $px.B -gt 140 -and $px.R -lt 80) {
                $cyanCount++
            }
        }
    }
    $hasOptionNumbers = $cyanCount -gt 3

    # --- Signal 3: Look for white/bright text with specific patterns in bottom area ---
    # Permission prompts typically have more bright text lines in bottom 200px
    $brightLineCount = 0
    for ($y = $scanBottomStart; $y -lt $h; $y += 8) {
        $lineHasBright = $false
        for ($x = 50; $x -lt [math]::Min(400, $w); $x += 6) {
            $px = $bmp.GetPixel($x, $y)
            if ($px.R -gt 200 -and $px.G -gt 200 -and $px.B -gt 200) {
                $lineHasBright = $true
                break
            }
        }
        if ($lineHasBright) { $brightLineCount++ }
    }
    $hasMultipleBrightLines = $brightLineCount -gt 3

    # Decision: must NOT have send button AND must have option indicators
    if (-not $hasSendButton -and ($hasOptionNumbers -or $hasMultipleBrightLines)) {
        return $true
    }

    return $false
}

function Send-Approval([IntPtr]$hwnd) {
    $cursorBefore = [System.Windows.Forms.Cursor]::Position
    $prevWindow = $w32::GetForegroundWindow()

    # Restore if minimized, bring to front
    $w32::ShowWindow($hwnd, 9) | Out-Null   # SW_RESTORE
    Start-Sleep -Milliseconds 150
    $w32::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 200

    # Send "2" = "Yes, don't ask again"
    [System.Windows.Forms.SendKeys]::SendWait("2")
    Start-Sleep -Milliseconds 100

    # Restore previous window and cursor
    if ($prevWindow -ne [IntPtr]::Zero) {
        $w32::SetForegroundWindow($prevWindow) | Out-Null
    }
    [System.Windows.Forms.Cursor]::Position = $cursorBefore
}

function Test-IsOnLeftScreen([IntPtr]$hwnd) {
    if ($AnyScreen) { return $true }
    $rc = New-Object CodexBot.Win32+RECT
    $w32::GetWindowRect($hwnd, [ref]$rc) | Out-Null
    $cx = ($rc.Left + $rc.Right) / 2
    return ($cx -ge $leftScreenMinX -and $cx -lt $leftScreenMaxX)
}

function Write-Status($msg, $color = "Gray") {
    $remaining = [math]::Round(($deadline - (Get-Date)).TotalMinutes, 1)
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host "[$ts] " -NoNewline -ForegroundColor DarkGray
    Write-Host "$msg " -NoNewline -ForegroundColor $color
    Write-Host "(${remaining}m left, ${totalApproved} approved)" -ForegroundColor DarkGray
}

# ---- Banner ----
$banner = @"

   ____          _           ____        _
  / ___|___   __| | _____  _| __ )  ___ | |_
 | |   / _ \ / _` |/ _ \ \/ /  _ \ / _ \| __|
 | |__| (_) | (_| |  __/>  <| |_) | (_) | |_
  \____\___/ \__,_|\___/_/\_\____/ \___/ \__|  v1.0

"@

Write-Host $banner -ForegroundColor Cyan
Write-Host "  Config:" -ForegroundColor White
Write-Host "    Duration:  $Duration min" -ForegroundColor Gray
Write-Host "    Interval:  ${Interval}s" -ForegroundColor Gray
Write-Host "    Screen:    $(if ($AnyScreen) {'Any'} else {'Left only'})" -ForegroundColor Gray
Write-Host "    Debug:     $(if ($Debug) {'ON (saving screenshots)'} else {'OFF'})" -ForegroundColor Gray
Write-Host ""
Write-Host "  Press 'q' to stop" -ForegroundColor Yellow
Write-Host "  ────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# ---- Main Loop ----
while ((Get-Date) -lt $deadline) {
    # Check for quit key
    try {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q') {
                Write-Host ""
                Write-Status "Stopped by user." "Yellow"
                break
            }
        }
    } catch {}

    $totalChecks++

    # Find Codex window
    $proc = Find-CodexWindow
    if (-not $proc) {
        Write-Status "Codex window not found. Waiting..." "DarkYellow"
        Start-Sleep -Seconds $Interval
        continue
    }

    $hwnd = $proc.MainWindowHandle

    # Restore if minimized
    if ($w32::IsIconic($hwnd)) {
        $w32::ShowWindow($hwnd, 4) | Out-Null   # SW_SHOWNOACTIVATE
        Start-Sleep -Milliseconds 300
    }

    # Check screen position
    if (-not (Test-IsOnLeftScreen $hwnd)) {
        Write-Status "Codex on wrong screen. Skipping." "DarkGray"
        Start-Sleep -Seconds $Interval
        continue
    }

    # Capture and analyze
    $bmp = $null
    $isPrompt = $false
    try {
        $bmp = Get-WindowBitmap $hwnd
        if ($bmp) {
            # Debug: save screenshot
            if ($Debug) {
                $ts = Get-Date -Format 'HHmmss'
                $bmp.Save("$screenshotDir\codex_$ts.png", [System.Drawing.Imaging.ImageFormat]::Png)
                # Keep only last 10
                $old = Get-ChildItem $screenshotDir -Filter "codex_*.png" | Sort-Object LastWriteTime | Select-Object -SkipLast 10
                foreach ($f in $old) { Remove-Item $f.FullName -Force }
            }

            $isPrompt = Test-IsPermissionPrompt $bmp
            $bmp.Dispose()
            $bmp = $null
        }
    } catch {
        if ($bmp) { $bmp.Dispose() }
    }

    if ($isPrompt) {
        Send-Approval $hwnd
        $totalApproved++
        Write-Status "PROMPT detected! Sent '2' to approve." "Green"
    } else {
        Write-Status "No prompt. Codex working..." "DarkCyan"
    }

    # Wait with key check
    for ($i = 0; $i -lt $Interval; $i++) {
        try {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q') {
                    Write-Host ""
                    Write-Status "Stopped by user." "Yellow"
                    $deadline = Get-Date  # exit outer loop
                    break
                }
            }
        } catch {}
        Start-Sleep -Seconds 1
    }
}

# ---- Summary ----
$elapsed = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
Write-Host ""
Write-Host "  ────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  Session Summary:" -ForegroundColor White
Write-Host "    Runtime:    ${elapsed} min" -ForegroundColor Gray
Write-Host "    Checks:     $totalChecks" -ForegroundColor Gray
Write-Host "    Approved:   $totalApproved" -ForegroundColor $(if ($totalApproved -gt 0) {"Green"} else {"Gray"})
Write-Host "  ────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  CodexBot finished." -ForegroundColor Cyan
