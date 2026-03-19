# test-07-release-fast.ps1 — ReleaseFast build verification (Issue #122)
# Launches ReleaseFast ghostty, verifies init completes, D3D11 renders, CP works.
#
# NO SendKeys, NO mouse, NO window activation. Launch → log → CP ping → kill.
# Validates: ReleaseFast startup (#122), provider path (#122), CP DLL, D3D11 Present

$ErrorActionPreference = 'Continue'
$testName = "test-07-release-fast"

Import-Module "$PSScriptRoot\test-helpers.psm1" -Force

$exePath = Join-Path $PSScriptRoot "..\..\zig-out-winui3\bin\ghostty.exe"
$exePath = (Resolve-Path $exePath -ErrorAction Stop).Path

if (-not (Test-Path $exePath)) {
    throw "$testName FAIL: ghostty.exe not found at $exePath"
}

$agentCtl = Join-Path $env:USERPROFILE "agent-relay\target\debug\agent-ctl.exe"

$logPath = Join-Path $env:TEMP "ghostty_debug.log"

# Kill any existing ghostty
Get-Process -Name ghostty -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# Clear log
if (Test-Path $logPath) { Remove-Item $logPath -Force }

Write-Host "  Launching ghostty (ReleaseFast) ..." -ForegroundColor DarkGray

$env:GHOSTTY_CONTROL_PLANE = "1"
$proc = Start-Process -FilePath $exePath -PassThru
$procId = $proc.Id
Write-Host "  PID = $procId" -ForegroundColor DarkGray
Test-Assert -Condition ($procId -gt 0) -Message "$testName - process started (PID=$procId)"

# Wait for process to stabilize (10s)
Start-Sleep -Seconds 10

# Check process is still alive
$proc.Refresh()
Test-Assert -Condition (-not $proc.HasExited) -Message "$testName - process alive after 10s"

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

# Verify build mode (early log lines go to stderr before attachDebugConsole redirects to file)
# Check file size as proxy — ReleaseFast exe is ~29MB, Debug is ~70MB
$exeSize = (Get-Item $exePath).Length
$isRelease = $exeSize -lt 50MB
Write-Host "  exe size: $([math]::Round($exeSize/1MB, 1))MB (ReleaseFast < 50MB)" -ForegroundColor DarkGray
Test-Assert -Condition $isRelease -Message "$testName - binary is ReleaseFast ($([math]::Round($exeSize/1MB))MB)"

# Verify init completed
$hasInitOk = $logContent -match "App.init: EXIT OK"
Test-Assert -Condition $hasInitOk -Message "$testName - App.init completed"

# Verify XAML init (Issue #122: activateXamlType via provider)
$hasXamlOk = $logContent -match "initXaml step 8"
Test-Assert -Condition $hasXamlOk -Message "$testName - initXaml step 8 reached"

# Verify no E_NOTIMPL crash
$hasNotImpl = $logContent -match "0x80004001"
Test-Assert -Condition (-not $hasNotImpl) -Message "$testName - no E_NOTIMPL error"

# Verify D3D11 rendering
$hasPresent = $logContent -match "Present OK"
Test-Assert -Condition $hasPresent -Message "$testName - D3D11 rendering active"

# Verify activateXamlType uses provider (not RoActivateInstance fallback)
$hasProvider = $logContent -match "activateXamlType\(provider\)"
Test-Assert -Condition $hasProvider -Message "$testName - activateXamlType uses IXamlMetadataProvider"

# Verify CP DLL loaded
$hasCpOk = $logContent -match "control plane DLL started"
Test-Assert -Condition $hasCpOk -Message "$testName - Control plane DLL loaded"

# Verify DispatcherQueue obtained
$hasDq = $logContent -match "IDispatcherQueue obtained"
Test-Assert -Condition $hasDq -Message "$testName - DispatcherQueue initialized"

# Verify CP session via agent-ctl ping
if (Test-Path $agentCtl) {
    $sessionDir = Join-Path $env:LOCALAPPDATA "WindowsTerminal\control-plane\winui3\sessions"
    $sessionFile = Get-ChildItem "$sessionDir\ghostty-$procId-*.session" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($sessionFile) {
        $sn = $sessionFile.BaseName
        $pong = & $agentCtl ping $sn 2>&1 | Out-String
        $cpAlive = $pong -match "PONG"
        Test-Assert -Condition $cpAlive -Message "$testName - CP session responds to PING ($sn)"
    } else {
        Write-Host "  INFO: No CP session file found for PID $procId (non-fatal)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  INFO: agent-ctl not found, skipping CP ping test" -ForegroundColor Yellow
}

# Frame profiler check
$profileLines = ($logContent -split "`n") | Where-Object { $_ -match "frame-profile:" }
if ($profileLines.Count -gt 0) {
    Write-Host "  PASS: frame-profile data ($($profileLines.Count) reports)" -ForegroundColor Green
    $profileLines | Select-Object -First 2 | ForEach-Object { Write-Host "    $($_.Trim())" -ForegroundColor Cyan }
}

# Cleanup
Write-Host "  Stopping ghostty ..." -ForegroundColor DarkGray
$proc | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

Write-Host "  $testName PASSED" -ForegroundColor Green
