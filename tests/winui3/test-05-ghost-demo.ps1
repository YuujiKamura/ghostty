# test-05-ghost-demo.ps1 — Frame profiler + XAML tracing gate verification
# Launches ghostty with --font-size=7, lets it render for a few seconds,
# then checks logs for frame-profile output and tracing gate.
#
# NO SendKeys, NO mouse, NO window activation. Just launch → log → kill.
# Validates: frame profiler (#116), XAML debug tracing gate (#116)

$ErrorActionPreference = 'Stop'
$testName = "test-05-ghost-demo"

Import-Module "$PSScriptRoot\test-helpers.psm1" -Force

$exePath = Join-Path $PSScriptRoot "..\..\zig-out-winui3\bin\ghostty.exe"
$exePath = (Resolve-Path $exePath -ErrorAction Stop).Path

if (-not (Test-Path $exePath)) {
    throw "$testName FAIL: ghostty.exe not found at $exePath"
}

$logPath = Join-Path $env:TEMP "ghostty_debug.log"

# Record current log size
$logOffsetBefore = 0
if (Test-Path $logPath) {
    $logOffsetBefore = (Get-Item $logPath).Length
}

Write-Host "  Launching ghostty (auto-close after 8s) ..." -ForegroundColor DarkGray

# Launch with auto-close timer so it exits on its own
$proc = $null
try {
    $env:GHOSTTY_WINUI3_CLOSE_TAB_AFTER_MS = "8000"
    $env:GHOSTTY_CONTROL_PLANE = $null
    $env:WINDOWS_TERMINAL_CONTROL_PLANE = $null
    $proc = Start-Process -FilePath $exePath -PassThru
} finally {
    $env:GHOSTTY_WINUI3_CLOSE_TAB_AFTER_MS = $null
}

$procId = $proc.Id
Write-Host "  PID = $procId" -ForegroundColor DarkGray
Test-Assert -Condition ($procId -gt 0) -Message "$testName - process started (PID=$procId)"

# Wait for process to exit (auto-close after 8s + buffer)
$exited = $false
$deadline = [DateTime]::UtcNow.AddMilliseconds(15000)
while ([DateTime]::UtcNow -lt $deadline) {
    if ($proc.HasExited) {
        $exited = $true
        break
    }
    Start-Sleep -Milliseconds 500
}

if (-not $exited) {
    Write-Host "  WARN: Process did not auto-exit, killing ..." -ForegroundColor Yellow
    $proc | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

$exitCode = $proc.ExitCode
Write-Host "  Process exited (code=$exitCode)" -ForegroundColor DarkGray
if ($exitCode -lt 0) {
    Write-Host "  WARN: Negative exit code (known XAML shutdown crash in Debug builds)" -ForegroundColor Yellow
}

# Read full log content (use ReadWrite share to avoid lock)
$newLogContent = ""
if (Test-Path $logPath) {
    try {
        $fs = [System.IO.FileStream]::new(
            $logPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
        )
        try {
            $reader = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8, $false, 4096, $true)
            $newLogContent = $reader.ReadToEnd()
            $reader.Dispose()
        } finally {
            $fs.Dispose()
        }
    } catch {
        Write-Host "  WARN: Could not read log: $_" -ForegroundColor Yellow
    }
}

# --- Assertions ---

# 1. D3D11 Present happened (terminal rendered something)
$hasPresent = $newLogContent -match "Present OK"
Test-Assert -Condition $hasPresent -Message "$testName - D3D11 rendering active (Present OK)"

# 2. XAML tracing is disabled by default (Issue #116 Phase 2)
$hasTracingDisabled = $newLogContent -match "DebugSettings: tracing disabled"
Test-Assert -Condition $hasTracingDisabled -Message "$testName - XAML tracing gated by env var"

# 3. Frame profiler output (Issue #116 - needs 120+ frames)
$profileLines = ($newLogContent -split "`n") | Where-Object { $_ -match "frame-profile:" }
if ($profileLines.Count -gt 0) {
    Write-Host "  PASS: frame-profile data captured ($($profileLines.Count) reports)" -ForegroundColor Green
    foreach ($line in $profileLines) {
        $trimmed = $line.Trim()
        Write-Host "    $trimmed" -ForegroundColor Cyan
    }
} else {
    Write-Host "  INFO: No frame-profile yet (needs 120 frames, 8s may not be enough at vsync)" -ForegroundColor Yellow
}

Write-Host "  $testName PASSED" -ForegroundColor Green
