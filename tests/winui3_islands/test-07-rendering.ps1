param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# Test 7: Rendering — 画面キャプチャからクライアント領域に描画の変化があることを確認

$ErrorActionPreference = 'Stop'
$testName = "test-07-rendering"

$rect = Get-WindowPosition -Hwnd $Hwnd
$dpi = [Win32]::GetDpiForWindow($Hwnd)
$titlebarHeight = [int](40 * ($dpi / 96.0))
$captureX = $rect.Left + 24
$captureY = $rect.Top + $titlebarHeight + 12
$captureWidth = [Math]::Max(120, [Math]::Min(320, $rect.Width - 48))
$captureHeight = [Math]::Max(80, [Math]::Min(140, $rect.Height - $titlebarHeight - 24))

Test-Assert -Condition ($captureWidth -gt 0 -and $captureHeight -gt 0) -Message "capture region is valid"

Start-Sleep -Milliseconds 1200
$bmp = Capture-ScreenRegion -X $captureX -Y $captureY -Width $captureWidth -Height $captureHeight
try {
    $uniqueColors = Get-BitmapUniqueColorCount -Bitmap $bmp
    $outDir = Join-Path $PSScriptRoot "..\..\tmp\winui3_islands"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $outPath = Join-Path $outDir "test-07-rendering.png"
    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)

    Write-Host "  Capture saved to $outPath" -ForegroundColor Gray
    Write-Host "  Sampled unique colors: $uniqueColors" -ForegroundColor Gray

    Test-Assert -Condition ($uniqueColors -ge 2) -Message "captured client region is not a single flat color"
} finally {
    $bmp.Dispose()
}

Write-Host "PASS: $testName — Client capture shows rendered color variation" -ForegroundColor Green
