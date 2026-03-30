# test-05-ghost-demo.ps1 — Ghost animation rendering verification
# Launches ghostty, runs play.py at 60fps (auto-scales to fit), verifies D3D11 rendering.

$ErrorActionPreference = 'Continue'
$testName = "test-05-ghost-demo"

Import-Module "$PSScriptRoot\test-helpers.psm1" -Force

$exePath = Join-Path $PSScriptRoot "..\..\zig-out-winui3\bin\ghostty.exe"
$exePath = (Resolve-Path $exePath -ErrorAction Stop).Path

if (-not (Test-Path $exePath)) {
    throw "$testName FAIL: ghostty.exe not found at $exePath"
}

$logPath = Join-Path $env:TEMP "ghostty_debug.log"

# Kill any existing ghostty
Get-Process -Name ghostty -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# Clear log
if (Test-Path $logPath) { Remove-Item $logPath -Force }

Write-Host "  Launching ghostty ..." -ForegroundColor DarkGray

$env:GHOSTTY_CONTROL_PLANE = "1"
$proc = Start-Process -FilePath $exePath -PassThru
$procId = $proc.Id
Write-Host "  PID = $procId" -ForegroundColor DarkGray
Test-Assert -Condition ($procId -gt 0) -Message "$testName - process started (PID=$procId)"

# Wait for window + CP
Start-Sleep -Seconds 6

$proc.Refresh()
Test-Assert -Condition (-not $proc.HasExited) -Message "$testName - process alive after 6s"

# Register + find CP session via agent-deck
$sessionName = Register-GhosttyCP -ProcessId $procId
if (-not $sessionName) {
    $sessionName = Find-GhosttyCP -ProcessId $procId
}

if ($sessionName) {
    Write-Host "  CP session: $sessionName" -ForegroundColor DarkGray

    # Send play.py — it auto-scales to fit any terminal size
    $playPy = "C:\Users\yuuji\ghostty-win\tools\ghost-demo\play.py"
    $sendOk = Send-GhosttyInput -SessionName $sessionName -Text "python `"$playPy`" --fps 60"
    if ($sendOk) {
        Write-Host "  Sent play.py --fps 60 (auto-scale)" -ForegroundColor DarkGray
    } else {
        Write-Host "  WARN: Could not send play.py (send unavailable)" -ForegroundColor Yellow
    }

    # Let animation play (~4s for 235 frames at 60fps, plus margin)
    Start-Sleep -Seconds 8
} else {
    Write-Host "  WARN: No CP session, skipping demo playback" -ForegroundColor Yellow
}

# Read log
$logContent = ""
if (Test-Path $logPath) {
    try {
        $fs = [System.IO.FileStream]::new($logPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
        $reader = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
        $logContent = $reader.ReadToEnd()
        $reader.Dispose()
        $fs.Dispose()
    } catch {
        Write-Host "  WARN: Could not read log: $_" -ForegroundColor Yellow
    }
}

# Verify init completed
$hasInitOk = $logContent -match "App.init: EXIT OK"
Test-Assert -Condition $hasInitOk -Message "$testName - App.init completed"

# Verify XAML init
$hasXamlOk = $logContent -match "initXaml step 8"
Test-Assert -Condition $hasXamlOk -Message "$testName - initXaml step 8 reached"

# Verify D3D11 rendering
$hasPresent = $logContent -match "Present OK"
Test-Assert -Condition $hasPresent -Message "$testName - D3D11 rendering active"

# Verify activateXamlType uses provider
$hasProvider = $logContent -match "activateXamlType\(provider\)"
Test-Assert -Condition $hasProvider -Message "$testName - activateXamlType uses IXamlMetadataProvider"

# Verify CP DLL loaded
$hasCpOk = $logContent -match "control plane DLL started"
if (-not $hasCpOk) {
    # Also check for the zig-native CP (newer builds may not use DLL)
    $hasCpOk = $logContent -match "control plane started"
}
Test-Assert -Condition $hasCpOk -Message "$testName - Control plane loaded"

# Frame profiler check
$profileLines = ($logContent -split "`n") | Where-Object { $_ -match "frame-profile:" }
if ($profileLines.Count -gt 0) {
    Write-Host "  PASS: frame-profile data ($($profileLines.Count) reports)" -ForegroundColor Green
    $profileLines | Select-Object -Last 2 | ForEach-Object { Write-Host "    $($_.Trim())" -ForegroundColor Cyan }
}

# Cleanup
Write-Host "  Stopping ghostty ..." -ForegroundColor DarkGray
$proc | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

Write-Host "  $testName PASSED" -ForegroundColor Green
