$ErrorActionPreference = "Stop"

. "$PSScriptRoot\winui3-test-lib.ps1"

$repoRoot = Split-Path -Parent $PSScriptRoot
$exePath = Join-Path $repoRoot "zig-out\bin\ghostty.exe"
$tmpDir = Join-Path $repoRoot "tmp"
$screenshotPath = Join-Path $repoRoot "visual_smoke_test.png"
$debugLogPath = Join-Path $repoRoot "debug.log"

function Find-GhosttyWindowAny {
    param(
        [Parameter(Mandatory)][pscustomobject]$Session,
        [int]$TimeoutMs = 20000
    )

    try {
        return Find-GhosttyWindow -StderrPath $Session.StderrPath -TimeoutMs 1500
    } catch {}

    $line = Wait-LogLine -Path $debugLogPath -Pattern "step 4 OK: HWND=0x" -TimeoutMs $TimeoutMs
    if ($line -match "HWND=0x([0-9a-fA-F]+)") {
        $hwnd = [IntPtr][System.Convert]::ToInt64($Matches[1], 16)
        if ([Win32]::IsWindowVisible($hwnd)) {
            return $hwnd
        }
        throw "HWND from debug.log is not visible: 0x$($Matches[1])"
    }
    throw "HWND pattern not found in debug.log"
}

Write-Host "Starting Ghostty for visual smoke test..."
"" | Set-Content -Path $debugLogPath -Encoding utf8
$session = Start-Ghostty -ExePath $exePath -TmpDir $tmpDir -WorkingDirectory $repoRoot

try {
    Write-Host "Waiting for Ghostty HWND from startup log..."
    $hwnd = Find-GhosttyWindowAny -Session $session -TimeoutMs 20000

    Start-Sleep -Seconds 2

    $rect = New-Object RECT
    if (-not [Win32]::GetWindowRect($hwnd, [ref]$rect)) {
        throw "GetWindowRect failed for HWND=0x$($hwnd.ToString('X'))"
    }

    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if ($width -le 0 -or $height -le 0) {
        throw "Invalid window size ($width x $height)."
    }

    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
    $bmp.Save($screenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()

    Write-Host "Screenshot saved to: $screenshotPath"

    $pixelColor = $bmp.GetPixel([int]($width / 2), [int]($height / 2))
    Write-Host "Center Pixel Color: R=$($pixelColor.R), G=$($pixelColor.G), B=$($pixelColor.B)"

    $bmp.Dispose()

    if ($pixelColor.R -gt 240 -and $pixelColor.G -gt 240 -and $pixelColor.B -gt 240) {
        Write-Host "FAILED: Detected a white screen." -ForegroundColor Red
        exit 1
    }

    Write-Host "Visual test PASSED: center is not white." -ForegroundColor Green
}
finally {
    Write-Host "Stopping Ghostty process..."
    Stop-Ghostty -Session $session -TimeoutMs 2000 | Out-Null
}
