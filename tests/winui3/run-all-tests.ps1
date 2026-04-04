# run-all-tests.ps1  Ewinui3 integration test runner (reorganized)
# Usage: pwsh.exe -File run-all-tests.ps1
#
# test-01-lifecycle runs FIRST and SEPARATELY (manages its own process).
# Then a shared ghostty is launched for tests 02a through 04.

param(
    [string]$ExePath,
    [switch]$SkipBuild,
    [switch]$OnlyFailed
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

# --- OnlyFailed: load previous results and build filter set ---
$failedNames = $null
if ($OnlyFailed) {
    $lastResultsPath = Join-Path $PSScriptRoot ".last-results.json"
    if (-not (Test-Path $lastResultsPath)) {
        Write-Host "No previous failures found. Run full suite first." -ForegroundColor Yellow
        exit 0
    }
    $lastResults = Get-Content $lastResultsPath -Raw | ConvertFrom-Json
    $failedNames = @($lastResults | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object { $_.Name })
    if ($failedNames.Count -eq 0) {
        Write-Host "No previous failures found. Run full suite first." -ForegroundColor Yellow
        exit 0
    }
    Write-Host "`n=== Re-running $($failedNames.Count) previously failed test(s) ===" -ForegroundColor Magenta
    $failedNames | ForEach-Object { Write-Host "  - $_" -ForegroundColor Magenta }
}

# ============================================================
# Phase 1: Lifecycle test (own process, no shared ghostty)
# ============================================================
Write-Host "`n=== Phase 1: Lifecycle Test (standalone) ===" -ForegroundColor Cyan

$lifecycleTest = Join-Path $PSScriptRoot "test-01-lifecycle.ps1"
if ($failedNames -and ("test-01-lifecycle" -notin $failedNames)) {
    Write-Host "  SKIP: test-01-lifecycle (not in previous failures)" -ForegroundColor DarkGray
} elseif (Test-Path $lifecycleTest) {
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

# Clean stale ghostty session files (Force Kill doesn't trigger DLL cleanup)
$agentDeck = Join-Path $env:USERPROFILE "deckpilot\deckpilot.exe"
$ghosttySessionDir = Join-Path $env:LOCALAPPDATA "ghostty\control-plane\winui3\sessions"
foreach ($sessionDir in @($ghosttySessionDir, (Join-Path $env:LOCALAPPDATA "WindowsTerminal\control-plane\winui3\sessions"))) {
    if (Test-Path $sessionDir) {
        Get-ChildItem "$sessionDir\ghostty-*.session" -ErrorAction SilentlyContinue | ForEach-Object {
            $content = Get-Content $_.FullName -Raw
            if ($content -match 'pid=(\d+)') {
                $sessionPid = [int]$Matches[1]
                $liveProc = Get-Process -Id $sessionPid -ErrorAction SilentlyContinue
                $isGhostty = $liveProc -and ($liveProc.ProcessName -eq 'ghostty')
                if (-not $isGhostty) {
                    Remove-Item $_.FullName -Force
                    Write-Host "  Cleaned stale session: $($_.Name)" -ForegroundColor DarkGray
                }
            }
        }
    }
}

# Run base UI tests (no CP dependency)
$sharedTests = @(
    "test-02a-tabview",
    "test-02b-ime-overlay",
    "test-02c-drag-bar",
    "test-03-window-ops"
)

# CP-dependent tests run separately in Phase 2b
$cpTests = @(
    "test-02d-control-plane",
    "test-02e-agent-roundtrip",
    "test-04-keyboard",
    "test-06-ime-input"
)

# --- OnlyFailed: filter test arrays to previously-failed tests only ---
if ($failedNames) {
    $sharedTests = @($sharedTests | Where-Object { $_ -in $failedNames })
    $cpTests = @($cpTests | Where-Object { $_ -in $failedNames })
}

# Skip Ghostty launch entirely if no Phase 2/2b tests to run
$needSharedGhostty = ($sharedTests.Count -gt 0 -or $cpTests.Count -gt 0)
$proc = $null
$hwnd = [IntPtr]::Zero

if (-not $needSharedGhostty) {
    Write-Host "  SKIP: No Phase 2/2b tests to run" -ForegroundColor DarkGray
} else {
    $proc = Start-Ghostty -ExePath $ExePath

    try {
        $hwnd = Find-GhosttyWindow -ProcessId $proc.Id -TimeoutMs 15000
        Write-Host "  Window ready: HWND=0x$($hwnd.ToString('X'))" -ForegroundColor Green
    } catch {
        Write-Host "FATAL: Could not find Ghostty window: $_" -ForegroundColor Red
        Stop-Ghostty -Process $proc
        exit 1
    }

    # Give XAML time to fully initialize + CP DLL to register session
    Start-Sleep -Milliseconds 3000

    # Register + discover the ghostty CP session via deckpilot
    $env:GHOSTTY_CP_SESSION = ""
    $registered = Register-GhosttyCP -ProcessId $proc.Id
    if ($registered) {
        $env:GHOSTTY_CP_SESSION = $registered
        Write-Host "  CP session: $($env:GHOSTTY_CP_SESSION)" -ForegroundColor Green
    } else {
        # Fallback: try to discover without registration
        $discovered = Find-GhosttyCP -ProcessId $proc.Id
        if ($discovered) {
            $env:GHOSTTY_CP_SESSION = $discovered
            Write-Host "  CP session (discovered): $($env:GHOSTTY_CP_SESSION)" -ForegroundColor Green
        } else {
            Write-Host "  WARN: Could not identify ghostty CP session" -ForegroundColor Yellow
        }
    }
}

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

# ============================================================
# Phase 2b: Control-plane-dependent tests (same process, may be flaky)
# ============================================================
Write-Host "`n=== Phase 2b: Control Plane tests (CP-dependent) ===" -ForegroundColor Cyan

foreach ($testBaseName in $cpTests) {
    $testPath = Join-Path $PSScriptRoot "$testBaseName.ps1"
    if (-not (Test-Path $testPath)) {
        Write-Host "`n--- $testBaseName --- SKIP (not found)" -ForegroundColor Yellow
        continue
    }

    $startTime = [DateTime]::UtcNow
    $testOutput = $null
    try {
        $testOutput = & $testPath -Hwnd $hwnd -ProcessId $proc.Id 6>&1
        $elapsed = ([DateTime]::UtcNow - $startTime).TotalMilliseconds
        $results += @{ Name = $testBaseName; Status = "PASS"; Time = [int]$elapsed; Error = $null }
    } catch {
        $elapsed = ([DateTime]::UtcNow - $startTime).TotalMilliseconds
        $results += @{ Name = $testBaseName; Status = "FAIL"; Time = [int]$elapsed; Error = $_.Exception.Message }
        Write-Host "`n--- $testBaseName (FAIL) ---" -ForegroundColor Red
        if ($testOutput) { $testOutput | ForEach-Object { Write-Host "  $_" } }
        Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- Cleanup Phase 2 ---
if ($proc) {
    Write-Host "`n=== Stopping Ghostty (shared) ===" -ForegroundColor Cyan
    Stop-Ghostty -Process $proc
}

# ============================================================
# Phase 3: Standalone tests (own process, ReleaseFast verification)
# ============================================================
Write-Host "`n=== Phase 3: Standalone Tests ===" -ForegroundColor Cyan

$standaloneTests = @(
    "test-05-ghost-demo"
)
if ($failedNames) {
    $standaloneTests = @($standaloneTests | Where-Object { $_ -in $failedNames })
}

foreach ($testBaseName in $standaloneTests) {
    $testPath = Join-Path $PSScriptRoot "$testBaseName.ps1"
    if (-not (Test-Path $testPath)) {
        Write-Host "`n--- $testBaseName --- SKIP (not found)" -ForegroundColor Yellow
        continue
    }

    $startTime = [DateTime]::UtcNow
    $testOutput = $null
    try {
        $testOutput = & $testPath 6>&1
        $elapsed = ([DateTime]::UtcNow - $startTime).TotalMilliseconds
        $results += @{ Name = $testBaseName; Status = "PASS"; Time = [int]$elapsed; Error = $null }
    } catch {
        $elapsed = ([DateTime]::UtcNow - $startTime).TotalMilliseconds
        $results += @{ Name = $testBaseName; Status = "FAIL"; Time = [int]$elapsed; Error = $_.Exception.Message }
        Write-Host "`n--- $testBaseName (FAIL) ---" -ForegroundColor Red
        if ($testOutput) { $testOutput | ForEach-Object { Write-Host "  $_" } }
        Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
}

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

# --- Save results to .last-results.json for -OnlyFailed re-runs ---
$jsonResults = $results | ForEach-Object {
    [PSCustomObject]@{ Name = $_.Name; Status = $_.Status; Time = $_.Time; Error = $_.Error }
}
$jsonResults | ConvertTo-Json -Depth 2 | Set-Content (Join-Path $PSScriptRoot ".last-results.json") -Encoding UTF8

exit $failed
