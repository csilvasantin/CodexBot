# Quick test: capture Codex window and analyze it
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ([System.Management.Automation.PSTypeName]'CodexBotTest.Win32').Type) {
    Add-Type -Name Win32 -Namespace CodexBotTest -PassThru -MemberDefinition @"
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int Left, Top, Right, Bottom; }
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
        [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
"@ | Out-Null
}

$w32 = [CodexBotTest.Win32]

# Find Codex
$proc = Get-Process -Name "Codex" -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
    Select-Object -First 1

if (-not $proc) {
    $proc = Get-Process | Where-Object {
        $_.MainWindowTitle -like "*Codex*" -and $_.MainWindowHandle -ne [IntPtr]::Zero
    } | Select-Object -First 1
}

if (-not $proc) {
    Write-Host "Codex NOT found!" -ForegroundColor Red
    exit 1
}

Write-Host "Found: $($proc.ProcessName) (PID $($proc.Id)) - '$($proc.MainWindowTitle)'" -ForegroundColor Green

$hwnd = $proc.MainWindowHandle
$rc = New-Object CodexBotTest.Win32+RECT
$w32::GetWindowRect($hwnd, [ref]$rc) | Out-Null
$w = $rc.Right - $rc.Left
$h = $rc.Bottom - $rc.Top
Write-Host "Window: ${w}x${h} at ($($rc.Left), $($rc.Top))" -ForegroundColor Cyan

# Capture
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$gfx = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $gfx.GetHdc()
$w32::PrintWindow($hwnd, $hdc, 2) | Out-Null
$gfx.ReleaseHdc($hdc)
$gfx.Dispose()

$outPath = Join-Path $PSScriptRoot "screenshots\test_capture.png"
$dir = Split-Path $outPath
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
$bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Host "Saved: $outPath" -ForegroundColor Green

# Analyze signals
Write-Host "`n--- Signal Analysis ---" -ForegroundColor Yellow

# Signal 1: Green send button
$scanTop = [math]::Max(0, $h - 120)
$scanLeftHalf = [math]::Floor($w * 0.6)
$greenCount = 0
for ($y = $scanTop; $y -lt $h; $y += 2) {
    for ($x = $scanLeftHalf; $x -lt $w; $x += 2) {
        $px = $bmp.GetPixel($x, $y)
        if ($px.G -gt 110 -and $px.G -gt ($px.R * 1.4) -and $px.R -lt 110 -and $px.B -lt 130) {
            $greenCount++
        }
    }
}
Write-Host "  Green send button pixels: $greenCount $(if ($greenCount -gt 8) {'(FOUND)'} else {'(NOT FOUND)'})" -ForegroundColor $(if ($greenCount -gt 8) {'Green'} else {'Red'})

# Signal 2: Cyan options
$cyanCount = 0
$scanBottom250 = [math]::Max(0, $h - 250)
for ($y = $scanBottom250; $y -lt $h; $y += 2) {
    for ($x = 5; $x -lt [math]::Min(350, $w); $x += 2) {
        $px = $bmp.GetPixel($x, $y)
        if ($px.G -gt 130 -and $px.B -gt 130 -and $px.R -lt 90) {
            $cyanCount++
        }
    }
}
Write-Host "  Cyan option pixels: $cyanCount $(if ($cyanCount -gt 5) {'(OPTIONS FOUND)'} else {'(no options)'})" -ForegroundColor $(if ($cyanCount -gt 5) {'Yellow'} else {'Gray'})

# Signal 3: Bright text
$brightPixels = 0
for ($y = $scanBottom250; $y -lt $h; $y += 4) {
    for ($x = 30; $x -lt [math]::Min(500, $w); $x += 4) {
        $px = $bmp.GetPixel($x, $y)
        if ($px.R -gt 190 -and $px.G -gt 190 -and $px.B -gt 190) {
            $brightPixels++
        }
    }
}
Write-Host "  Bright text pixels: $brightPixels $(if ($brightPixels -gt 15) {'(BRIGHT TEXT)'} else {'(dim)'})" -ForegroundColor $(if ($brightPixels -gt 15) {'White'} else {'Gray'})

# Signal 4: Warning colors
$warningCount = 0
for ($y = $scanBottom250; $y -lt $h; $y += 3) {
    for ($x = 5; $x -lt [math]::Min(400, $w); $x += 3) {
        $px = $bmp.GetPixel($x, $y)
        if ($px.R -gt 180 -and $px.G -gt 140 -and $px.B -lt 80) {
            $warningCount++
        }
    }
}
Write-Host "  Warning/yellow pixels: $warningCount $(if ($warningCount -gt 3) {'(WARNING)'} else {'(none)'})" -ForegroundColor $(if ($warningCount -gt 3) {'DarkYellow'} else {'Gray'})

# Decision
$hasSendButton = $greenCount -gt 8
$hasOptions = $cyanCount -gt 5
$hasBright = $brightPixels -gt 15
$hasWarning = $warningCount -gt 3

Write-Host "`n--- Verdict ---" -ForegroundColor Yellow
if (-not $hasSendButton -and ($hasOptions -or ($hasWarning -and $hasBright))) {
    Write-Host "  PERMISSION PROMPT DETECTED - would send '2'" -ForegroundColor Green
} else {
    Write-Host "  No prompt - Codex is idle or working" -ForegroundColor Cyan
}

$bmp.Dispose()
Write-Host "`nCheck screenshot: $outPath" -ForegroundColor Gray
