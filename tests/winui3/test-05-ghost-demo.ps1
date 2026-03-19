# test-05-ghost-demo.ps1 — Ghost AA animation demo + frame profiler verification
# Launches ghostty, sends ghost demo via CP, verifies rendering and benchmark.
#
# NO SendKeys, NO mouse, NO window activation. Launch → CP send → log verify → kill.
# Validates: frame profiler (#116), background rendering (#116), ReleaseFast (#122)

# Use Continue globally — agent-ctl writes cargo warnings to stderr which PS treats as errors.
# Test failures are caught by Test-Assert (throws).
$ErrorActionPreference = 'Continue'
$testName = "test-05-ghost-demo"

Import-Module "$PSScriptRoot\test-helpers.psm1" -Force

$exePath = Join-Path $PSScriptRoot "..\..\zig-out-winui3\bin\ghostty.exe"
$exePath = (Resolve-Path $exePath -ErrorAction Stop).Path

if (-not (Test-Path $exePath)) {
    throw "$testName FAIL: ghostty.exe not found at $exePath"
}

$agentCtl = Join-Path $env:USERPROFILE "agent-relay\target\debug\agent-ctl.exe"
if (-not (Test-Path $agentCtl)) {
    throw "$testName FAIL: agent-ctl.exe not found at $agentCtl"
}

$playPy = Join-Path $PSScriptRoot "..\..\tools\ghost-demo\play.py"
$playPy = (Resolve-Path $playPy -ErrorAction Stop).Path
$playPy = $playPy -replace '\\', '/'

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

# Wait for CP session to appear (poll up to 15s)
Write-Host "  Waiting for CP session ..." -ForegroundColor DarkGray
$sessionName = $null
$sessionDir = Join-Path $env:LOCALAPPDATA "WindowsTerminal\control-plane\winui3\sessions"
$deadline = [DateTime]::UtcNow.AddSeconds(15)
while ([DateTime]::UtcNow -lt $deadline) {
    if ($proc.HasExited) {
        throw "$testName FAIL: ghostty exited prematurely (code=$($proc.ExitCode))"
    }
    # Clean dead sessions first
    & $agentCtl clean 2>&1 | Out-Null

    $sessions = Get-ChildItem "$sessionDir\ghostty-*.session" -ErrorAction SilentlyContinue
    foreach ($sf in $sessions) {
        $sn = $sf.BaseName
        # Extract PID from session name (format: ghostty-PID-PID)
        if ($sn -match "ghostty-(\d+)") {
            $sPid = [int]$Matches[1]
            # Only consider sessions matching our launched process
            if ($sPid -ne $procId) { continue }
        }
        $pong = & $agentCtl ping $sn 2>&1 | Out-String
        if ($pong -match "PONG") {
            $sessionName = $sn
            break
        }
    }
    if ($sessionName) { break }
    Start-Sleep -Milliseconds 500
}

Test-Assert -Condition ($null -ne $sessionName) -Message "$testName - CP session found ($sessionName)"
Write-Host "  Session: $sessionName" -ForegroundColor DarkGray

# Send ghost demo benchmark
Write-Host "  Sending ghost demo (benchmark mode) ..." -ForegroundColor DarkGray
$sendResult = & $agentCtl send $sessionName "python $playPy --benchmark" --enter 2>&1 | Out-String

# Wait for benchmark to complete (poll log for results, up to 20s)
Write-Host "  Waiting for benchmark results ..." -ForegroundColor DarkGray
$benchDone = $false
$deadline2 = [DateTime]::UtcNow.AddSeconds(20)
while ([DateTime]::UtcNow -lt $deadline2) {
    if (Test-Path $logPath) {
        # Benchmark prints to terminal stdout, not log. Check via TAIL.
        $tail = & $agentCtl read $sessionName --lines 5 2>&1 | Out-String
        if ($tail -match "avg\s+\d") {
            $benchDone = $true
            break
        }
    }
    Start-Sleep -Milliseconds 1000
}

# Read benchmark results from TAIL
$tailOutput = & $agentCtl read $sessionName --lines 15 2>&1 | Out-String
Write-Host "  --- Benchmark Output ---" -ForegroundColor Cyan
foreach ($line in ($tailOutput -split "`n")) {
    $trimmed = $line.Trim()
    if ($trimmed -match "Iter|avg|min|max|FPS|frames") {
        Write-Host "    $trimmed" -ForegroundColor Cyan
    }
}

Test-Assert -Condition $benchDone -Message "$testName - benchmark completed"

# Read log for rendering verification
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

# Assertions on log content
$hasPresent = $logContent -match "Present OK"
Test-Assert -Condition $hasPresent -Message "$testName - D3D11 rendering active (Present OK)"

$hasInitOk = $logContent -match "App.init: EXIT OK"
Test-Assert -Condition $hasInitOk -Message "$testName - App.init completed"

$hasCpOk = $logContent -match "control plane DLL started"
Test-Assert -Condition $hasCpOk -Message "$testName - Control plane active"

# Extract FPS from tail
if ($tailOutput -match "avg\s+[\d.]+\s+([\d.]+)") {
    $avgFps = [double]$Matches[1]
    Write-Host "  Average FPS: $avgFps" -ForegroundColor Green
    Test-Assert -Condition ($avgFps -gt 100) -Message "$testName - benchmark FPS > 100 (got $avgFps)"
}

# Cleanup
Write-Host "  Stopping ghostty ..." -ForegroundColor DarkGray
$proc | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

Write-Host "  $testName PASSED" -ForegroundColor Green
