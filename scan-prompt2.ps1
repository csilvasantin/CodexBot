# Scan full image for the green "En espera de aprobacion" badge and green/red diff markers
Add-Type -AssemblyName System.Drawing

$bmpPath = Join-Path $PSScriptRoot "screenshots\test_capture.png"
$bmp = [System.Drawing.Bitmap]::FromFile($bmpPath)
$w = $bmp.Width; $h = $bmp.Height
Write-Host "Image: ${w}x${h}" -ForegroundColor Cyan

# Scan FULL image for green pixels (the badge is in the sidebar, not bottom)
Write-Host "`n=== Green pixel scan (full image) ===" -ForegroundColor Yellow
$greenTotal = 0
$greenByRow = @{}
for ($y = 0; $y -lt $h; $y += 2) {
    $gInRow = 0
    for ($x = 0; $x -lt $w; $x += 2) {
        $px = $bmp.GetPixel($x, $y)
        # Any green: G significantly higher than R and B
        if ($px.G -gt 100 -and $px.G -gt ($px.R + 30) -and $px.G -gt ($px.B + 30)) {
            $greenTotal++
            $gInRow++
        }
    }
    if ($gInRow -gt 3) {
        $greenByRow[$y] = $gInRow
    }
}
Write-Host "  Total green pixels (sampled): $greenTotal" -ForegroundColor Green
Write-Host "  Rows with green:" -ForegroundColor Gray
$greenByRow.GetEnumerator() | Sort-Object Key | ForEach-Object {
    Write-Host "    y=$($_.Key): $($_.Value) green pixels" -ForegroundColor Green
}

# Scan for red pixels (the -2 in diff)
Write-Host "`n=== Red pixel scan ===" -ForegroundColor Yellow
$redTotal = 0
for ($y = 0; $y -lt $h; $y += 3) {
    for ($x = 0; $x -lt $w; $x += 3) {
        $px = $bmp.GetPixel($x, $y)
        if ($px.R -gt 150 -and $px.R -gt ($px.G + 50) -and $px.R -gt ($px.B + 50)) {
            $redTotal++
        }
    }
}
Write-Host "  Total red pixels: $redTotal" -ForegroundColor Red

# Check the sidebar area specifically (x: 0-380, look for the green badge)
Write-Host "`n=== Sidebar green badge scan (x:0-380) ===" -ForegroundColor Yellow
$badgeGreen = 0
for ($y = 200; $y -lt 400; $y += 1) {
    for ($x = 0; $x -lt 380; $x += 1) {
        $px = $bmp.GetPixel($x, $y)
        # Bright green background of badge
        if ($px.G -gt 140 -and $px.R -lt 200 -and $px.B -lt 120 -and ($px.G - $px.R) -gt 20) {
            $badgeGreen++
        }
    }
}
Write-Host "  Badge green pixels: $badgeGreen" -ForegroundColor Green

# Sample specific pixel colors around where the badge should be (y ~255, x ~100-300)
Write-Host "`n=== Pixel colors at badge area (y:240-270, x:100-320) ===" -ForegroundColor Yellow
$colorSet = @{}
for ($y = 240; $y -lt 275; $y += 1) {
    for ($x = 100; $x -lt 320; $x += 1) {
        $px = $bmp.GetPixel($x, $y)
        if ($px.R -gt 220 -and $px.G -gt 220 -and $px.B -gt 220) { continue }
        $key = "R:$($px.R) G:$($px.G) B:$($px.B)"
        if (-not $colorSet.ContainsKey($key)) { $colorSet[$key] = 0 }
        $colorSet[$key]++
    }
}
$colorSet.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 15 | ForEach-Object {
    Write-Host "  $($_.Key)  x$($_.Value)" -ForegroundColor Cyan
}

$bmp.Dispose()
