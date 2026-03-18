# run-all-tests.ps1 — winui3_islands integration test runner (UIA-based)
# Usage: pwsh.exe -File run-all-tests.ps1
#
# Launches ghostty.exe, runs all test-*.ps1 scripts using UI Automation.
# No SendInput or mouse cursor stealing — safe for background execution.

param(
    [string]$ExePath,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module "$PSScriptRoot\test-helpers.psm1" -Force

# --- Build check ---
if (-not $ExePath) {
    $ExePath = Join-Path $PSScriptRoot "..\..\zig-out-winui3-islands\bin\ghostty.exe"
}

if (-not (Test-Path $ExePath)) {
    Write-Host "ERROR: ghostty.exe not found at $ExePath" -ForegroundColor Red
    Write-Host "Build first: ./build-winui3-islands.sh" -ForegroundColor Yellow
    exit 1
}

# --- Launch ---
Write-Host "`n=== Launching Ghostty (winui3_islands) ===" -ForegroundColor Cyan
$proc = Start-GhosttyIslands -ExePath $ExePath
$hwnd = [IntPtr]::Zero

try {
    $hwnd = Find-GhosttyWindow -ProcessId $proc.Id -TimeoutMs 15000
    Write-Host "  Window ready: HWND=0x$($hwnd.ToString('X'))" -ForegroundColor Green
} catch {
    Write-Host "FATAL: Could not find Ghostty window: $_" -ForegroundColor Red
    Stop-GhosttyIslands -Process $proc
    exit 1
}

# Give XAML time to fully initialize
Start-Sleep -Milliseconds 2000

# --- Run tests ---
$tests = Get-ChildItem "$PSScriptRoot\test-*.ps1" | Sort-Object Name
$results = @()

foreach ($test in $tests) {
    $name = $test.BaseName
    Write-Host "`n--- $name ---" -ForegroundColor Cyan

    $startTime = [DateTime]::UtcNow
    try {
        & $test.FullName -Hwnd $hwnd -ProcessId $proc.Id
        $elapsed = ([DateTime]::UtcNow - $startTime).TotalMilliseconds
        $results += @{ Name = $name; Status = "PASS"; Time = [int]$elapsed; Error = $null }
    } catch {
        $elapsed = ([DateTime]::UtcNow - $startTime).TotalMilliseconds
        $results += @{ Name = $name; Status = "FAIL"; Time = [int]$elapsed; Error = $_.Exception.Message }
        Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- Cleanup ---
Write-Host "`n=== Stopping Ghostty ===" -ForegroundColor Cyan
Stop-GhosttyIslands -Process $proc

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
