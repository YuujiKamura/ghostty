# run-all-tests.ps1 — winui3 integration test runner (reorganized)
# Usage: pwsh.exe -File run-all-tests.ps1
#
# test-01-lifecycle runs FIRST and SEPARATELY (manages its own process).
# Then a shared ghostty is launched for tests 02a through 04.

param(
    [string]$ExePath,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module "$PSScriptRoot\test-helpers.psm1" -Force

# --- Build check ---
if (-not $ExePath) {
    $ExePath = Join-Path $PSScriptRoot "..\..\zig-out-winui3\bin\ghostty.exe"
}

if (-not (Test-Path $ExePath)) {
    Write-Host "ERROR: ghostty.exe not found at $ExePath" -ForegroundColor Red
    Write-Host "Build first: ./build-winui3.sh" -ForegroundColor Yellow
    exit 1
}

$results = @()

# ============================================================
# Phase 1: Lifecycle test (own process, no shared ghostty)
# ============================================================
Write-Host "`n=== Phase 1: Lifecycle Test (standalone) ===" -ForegroundColor Cyan

$lifecycleTest = Join-Path $PSScriptRoot "test-01-lifecycle.ps1"
if (Test-Path $lifecycleTest) {
    $name = "test-01-lifecycle"
    $startTime = [DateTime]::UtcNow
    $testOutput = $null
    try {
        $testOutput = & $lifecycleTest 6>&1
        $elapsed = ([DateTime]::UtcNow - $startTime).TotalMilliseconds
        $results += @{ Name = $name; Status = "PASS"; Time = [int]$elapsed; Error = $null }
    } catch {
        $elapsed = ([DateTime]::UtcNow - $startTime).TotalMilliseconds
        $results += @{ Name = $name; Status = "FAIL"; Time = [int]$elapsed; Error = $_.Exception.Message }
        Write-Host "`n--- $name (FAIL) ---" -ForegroundColor Red
        if ($testOutput) { $testOutput | ForEach-Object { Write-Host "  $_" } }
        Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "  SKIP: test-01-lifecycle.ps1 not found" -ForegroundColor Yellow
}

# ============================================================
# Phase 2: Shared-process tests (02a through 04)
# ============================================================
Write-Host "`n=== Phase 2: Launching Ghostty for shared tests ===" -ForegroundColor Cyan
$env:GHOSTTY_CONTROL_PLANE = "1"
$proc = Start-Ghostty -ExePath $ExePath
$hwnd = [IntPtr]::Zero

try {
    $hwnd = Find-GhosttyWindow -ProcessId $proc.Id -TimeoutMs 15000
    Write-Host "  Window ready: HWND=0x$($hwnd.ToString('X'))" -ForegroundColor Green
} catch {
    Write-Host "FATAL: Could not find Ghostty window: $_" -ForegroundColor Red
    Stop-Ghostty -Process $proc
    exit 1
}

# Give XAML time to fully initialize
Start-Sleep -Milliseconds 2000

# Run tests 02a, 02b, 02c, 03, 04 in order
$sharedTests = @(
    "test-02a-tabview",
    "test-02b-ime-overlay",
    "test-02c-drag-bar",
    "test-02d-control-plane",
    "test-02e-agent-roundtrip",
    "test-03-window-ops",
    "test-04-keyboard"
)

foreach ($testBaseName in $sharedTests) {
    $testPath = Join-Path $PSScriptRoot "$testBaseName.ps1"
    if (-not (Test-Path $testPath)) {
        Write-Host "`n--- $testBaseName --- SKIP (not found)" -ForegroundColor Yellow
        continue
    }

    $startTime = [DateTime]::UtcNow
    $testOutput = $null
    try {
        # Capture test output; only show on failure
        $testOutput = & $testPath -Hwnd $hwnd -ProcessId $proc.Id 6>&1
        $elapsed = ([DateTime]::UtcNow - $startTime).TotalMilliseconds
        $results += @{ Name = $testBaseName; Status = "PASS"; Time = [int]$elapsed; Error = $null }
    } catch {
        $elapsed = ([DateTime]::UtcNow - $startTime).TotalMilliseconds
        $results += @{ Name = $testBaseName; Status = "FAIL"; Time = [int]$elapsed; Error = $_.Exception.Message }
        # Show captured output on failure for debugging
        Write-Host "`n--- $testBaseName (FAIL) ---" -ForegroundColor Red
        if ($testOutput) { $testOutput | ForEach-Object { Write-Host "  $_" } }
        Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- Cleanup ---
Write-Host "`n=== Stopping Ghostty ===" -ForegroundColor Cyan
Stop-Ghostty -Process $proc

# --- Summary ---
Write-Host "`n============================================" -ForegroundColor White
Write-Host "  TEST RESULTS" -ForegroundColor White
Write-Host "============================================" -ForegroundColor White

$passed = @($results | Where-Object { $_.Status -eq "PASS" }).Count
$failed = @($results | Where-Object { $_.Status -eq "FAIL" }).Count
$total = $results.Count

foreach ($r in $results) {
    $color = if ($r.Status -eq "PASS") { "Green" } else { "Red" }
    $timeStr = "$($r.Time)ms"
    $line = "  [{0}] {1} ({2})" -f $r.Status, $r.Name, $timeStr
    Write-Host $line -ForegroundColor $color
    if ($r.Error) {
        Write-Host "         $($r.Error)" -ForegroundColor DarkRed
    }
}

Write-Host "--------------------------------------------" -ForegroundColor White
$summaryColor = if ($failed -eq 0) { "Green" } else { "Red" }
Write-Host "  $passed/$total passed, $failed failed" -ForegroundColor $summaryColor
Write-Host "============================================`n" -ForegroundColor White

exit $failed
