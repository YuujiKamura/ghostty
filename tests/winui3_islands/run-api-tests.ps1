# run-api-tests.ps1 — API-only tests (no SendInput, no mouse, no focus stealing)
# Safe to run from CI or background. Tests: 01, 06, 09, 10

param([string]$ExePath)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module "$PSScriptRoot\test-helpers.psm1" -Force

if (-not $ExePath) {
    $ExePath = Join-Path $PSScriptRoot "..\..\zig-out-winui3-islands\bin\ghostty.exe"
}
if (-not (Test-Path $ExePath)) {
    Write-Host "ERROR: ghostty.exe not found at $ExePath" -ForegroundColor Red
    exit 1
}

$apiTests = @(
    "test-01-window-visible",
    "test-06-tabview",
    "test-09-ime",
    "test-10-dpi"
)

Write-Host "`n=== Launching Ghostty (API-only tests) ===" -ForegroundColor Cyan
$proc = Start-GhosttyIslands -ExePath $ExePath

try {
    $hwnd = Find-GhosttyWindow -ProcessId $proc.Id -TimeoutMs 15000
    Write-Host "  Window ready: HWND=0x$($hwnd.ToString('X'))" -ForegroundColor Green
} catch {
    Write-Host "FATAL: Could not find Ghostty window: $_" -ForegroundColor Red
    Stop-GhosttyIslands -Process $proc
    exit 1
}

Start-Sleep -Milliseconds 3000

$results = @()
foreach ($testName in $apiTests) {
    $testFile = Join-Path $PSScriptRoot "$testName.ps1"
    if (-not (Test-Path $testFile)) {
        Write-Host "  SKIP: $testName (file not found)" -ForegroundColor Yellow
        continue
    }
    Write-Host "`n--- $testName ---" -ForegroundColor Cyan
    try {
        & $testFile -Hwnd $hwnd
        $results += @{ Name = $testName; Status = "PASS" }
    } catch {
        $results += @{ Name = $testName; Status = "FAIL"; Error = $_.Exception.Message }
        Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n=== Stopping Ghostty ===" -ForegroundColor Cyan
Stop-GhosttyIslands -Process $proc

$passed = @($results | Where-Object { $_.Status -eq "PASS" }).Count
$failed = @($results | Where-Object { $_.Status -eq "FAIL" }).Count

Write-Host "`n=== RESULTS: $passed/$($results.Count) passed, $failed failed ===" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
foreach ($r in $results) {
    $color = if ($r.Status -eq "PASS") { "Green" } else { "Red" }
    Write-Host "  [$($r.Status)] $($r.Name)" -ForegroundColor $color
    if ($r.ContainsKey('Error')) { Write-Host "         $($r.Error)" -ForegroundColor DarkRed }
}

exit $failed
