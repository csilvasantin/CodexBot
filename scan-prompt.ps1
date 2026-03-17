# Deep scan of Codex bottom area to find prompt pixel patterns
Add-Type -AssemblyName System.Drawing

$bmpPath = Join-Path $PSScriptRoot "screenshots\test_capture.png"
if (-not (Test-Path $bmpPath)) { Write-Host "No screenshot found!"; exit 1 }

$bmp = [System.Drawing.Bitmap]::FromFile($bmpPath)
$w = $bmp.Width; $h = $bmp.Height
Write-Host "Image: ${w}x${h}" -ForegroundColor Cyan

# Scan bottom 400px row by row, report dominant non-white colors
Write-Host "`n=== Bottom 400px color analysis ===" -ForegroundColor Yellow
$startY = [math]::Max(0, $h - 400)

for ($y = $startY; $y -lt $h; $y += 8) {
    $colors = @{ dark=0; blue=0; green=0; red=0; orange=0; cyan=0; gray=0; white=0; other=0 }
    for ($x = 0; $x -lt $w; $x += 4) {
        $px = $bmp.GetPixel($x, $y)
        $r = $px.R; $g = $px.G; $b = $px.B

        if ($r -gt 230 -and $g -gt 230 -and $b -gt 230) { $colors.white++ }
        elseif ($r -lt 50 -and $g -lt 50 -and $b -lt 50) { $colors.dark++ }
        elseif ($r -lt 80 -and $g -lt 80 -and $b -lt 80) { $colors.gray++ }
        elseif ($b -gt 150 -and $r -lt 100) { $colors.blue++ }
        elseif ($g -gt 130 -and $r -lt 80 -and $b -lt 100) { $colors.green++ }
        elseif ($r -gt 200 -and $g -lt 80 -and $b -lt 80) { $colors.red++ }
        elseif ($r -gt 180 -and $g -gt 100 -and $b -lt 80) { $colors.orange++ }
        elseif ($g -gt 150 -and $b -gt 150 -and $r -lt 80) { $colors.cyan++ }
        else { $colors.other++ }
    }

    $nonWhite = $colors.dark + $colors.blue + $colors.green + $colors.red + $colors.orange + $colors.cyan + $colors.gray + $colors.other
    if ($nonWhite -gt 5) {
        $parts = @()
        foreach ($k in @('dark','gray','blue','green','red','orange','cyan','other')) {
            if ($colors[$k] -gt 0) { $parts += "${k}:$($colors[$k])" }
        }
        Write-Host "  y=$y  white:$($colors.white) | $($parts -join '  ')" -ForegroundColor $(if ($colors.blue -gt 3 -or $colors.green -gt 3 -or $colors.orange -gt 3 -or $colors.cyan -gt 3) { "Green" } else { "Gray" })
    }
}

# Detailed pixel dump of last 100px
Write-Host "`n=== Last 100px unique colors (non-white, non-near-white) ===" -ForegroundColor Yellow
$colorSet = @{}
$bottomStart = [math]::Max(0, $h - 100)
for ($y = $bottomStart; $y -lt $h; $y += 2) {
    for ($x = 0; $x -lt $w; $x += 2) {
        $px = $bmp.GetPixel($x, $y)
        if ($px.R -gt 220 -and $px.G -gt 220 -and $px.B -gt 220) { continue } # skip whites
        $key = "R:$($px.R) G:$($px.G) B:$($px.B)"
        if (-not $colorSet.ContainsKey($key)) { $colorSet[$key] = 0 }
        $colorSet[$key]++
    }
}

$colorSet.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 30 | ForEach-Object {
    Write-Host "  $($_.Key)  count: $($_.Value)" -ForegroundColor Cyan
}

$bmp.Dispose()
