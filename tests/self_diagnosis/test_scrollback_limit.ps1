#Requires -Version 5.1
<#
.SYNOPSIS
    Test for Issue #138: scrollback limit regression guard.

.DESCRIPTION
    Verifies:
    1. Config.zig scrollback-limit default is NOT 0 (must be a reasonable value)
    2. Screen.zig max_scrollback default is documented (0 = no scrollback)
    3. Terminal.zig max_scrollback default is a reasonable value
    4. App.zig diagnostic page scan is gated (not walking every tick)
    5. PageList.zig correctly handles max_size=0 as "no scrollback"

.NOTES
    Static analysis only. Does not build or run the application.
#>

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$pass = 0
$fail = 0

function Check([string]$Name, [bool]$Condition, [string]$Detail) {
    if ($Condition) {
        Write-Host "[PASS] $Name" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "[FAIL] $Name -- $Detail" -ForegroundColor Red
        $script:fail++
    }
}

# --- 1. Config.zig: scrollback-limit default ---
$configPath = Join-Path $RepoRoot "src\config\Config.zig"
$configContent = Get-Content $configPath -Raw

# Extract the scrollback-limit default value
$sbMatch = [regex]::Match($configContent, '@"scrollback-limit":\s*usize\s*=\s*(\d[\d_]*)')
Check "Config.zig has scrollback-limit field" `
    $sbMatch.Success `
    "scrollback-limit field not found in Config.zig"

if ($sbMatch.Success) {
    $sbDefault = $sbMatch.Groups[1].Value -replace '_', ''
    $sbValue = [long]$sbDefault

    Check "scrollback-limit default is not 0" `
        ($sbValue -ne 0) `
        "scrollback-limit default is 0 (would mean no scrollback)"

    Check "scrollback-limit default is reasonable (> 1000)" `
        ($sbValue -gt 1000) `
        "scrollback-limit default $sbValue is too small"

    Check "scrollback-limit default is not maxInt-like (< 1TB)" `
        ($sbValue -lt 1000000000000) `
        "scrollback-limit default $sbValue is too large (effectively unlimited)"

    Write-Host "  INFO: scrollback-limit default = $sbValue bytes" -ForegroundColor Cyan
}

# --- 2. Screen.zig: max_scrollback semantics ---
$screenPath = Join-Path $RepoRoot "src\terminal\Screen.zig"
$screenContent = Get-Content $screenPath -Raw

# Check that max_scrollback=0 is treated as "no scrollback"
$noScrollbackCheck = $screenContent -match 'no_scrollback.*=.*max_scrollback\s*==\s*0'
Check "Screen.zig: max_scrollback=0 means no_scrollback" `
    $noScrollbackCheck `
    "Expected no_scrollback = (max_scrollback == 0) pattern"

# --- 3. Terminal.zig: max_scrollback default ---
$terminalPath = Join-Path $RepoRoot "src\terminal\Terminal.zig"
$terminalContent = Get-Content $terminalPath -Raw

$termMatch = [regex]::Match($terminalContent, 'max_scrollback:\s*usize\s*=\s*(\d[\d_]*)')
Check "Terminal.zig has max_scrollback default" `
    $termMatch.Success `
    "max_scrollback field not found in Terminal.zig Options"

if ($termMatch.Success) {
    $termDefault = $termMatch.Groups[1].Value -replace '_', ''
    $termValue = [long]$termDefault

    Check "Terminal.zig max_scrollback default is not 0" `
        ($termValue -ne 0) `
        "Terminal.zig max_scrollback default is 0"

    Write-Host "  INFO: Terminal.zig max_scrollback default = $termValue" -ForegroundColor Cyan
}

# --- 4. App.zig: diagnostic page scan gating ---
$appPath = Join-Path $RepoRoot "src\apprt\winui3\App.zig"
$appContent = Get-Content $appPath -Raw

# Check that logDiagnosticSnapshot is gated (not called every tick)
$diagnosticGated = $appContent -match 'diagnostic_tick_count\s*%\s*diagnostic_interval'
Check "App.zig: diagnostic page scan is interval-gated" `
    $diagnosticGated `
    "logDiagnosticSnapshot should be gated by tick interval"

# Check that the diagnostic function walks pages (page_count variable + while loop)
$hasPageCount = $appContent -match 'var page_count.*=\s*0'
$hasWhileLoop = $appContent -match 'while\s*\(it\)\s*\|node\|'
Check "App.zig: diagnostic has page walk loop" `
    ($hasPageCount -and $hasWhileLoop) `
    "Expected page walk loop with page_count in logDiagnosticSnapshot"

# --- 5. Termio.zig: config flows to Terminal ---
$termioPath = Join-Path $RepoRoot "src\termio\Termio.zig"
$termioContent = Get-Content $termioPath -Raw

$configFlows = $termioContent -match 'max_scrollback.*=.*scrollback-limit'
Check "Termio.zig: config scrollback-limit flows to Terminal" `
    $configFlows `
    "Expected max_scrollback = ...scrollback-limit... in Termio.zig"

# --- 6. PageList.zig: max_size null vs 0 semantics ---
$pageListPath = Join-Path $RepoRoot "src\terminal\PageList.zig"
$pageListContent = Get-Content $pageListPath -Raw

# null means unlimited (maxInt)
$nullUnlimited = $pageListContent -match 'max_size\s+orelse\s+std\.math\.maxInt'
Check "PageList.zig: null max_size maps to maxInt (unlimited)" `
    $nullUnlimited `
    "Expected max_size orelse std.math.maxInt pattern"

# explicit_max_size=0 check exists in grow path
$zeroCheck = $pageListContent -match 'explicit_max_size\s*==\s*0'
Check "PageList.zig: explicit_max_size==0 check exists" `
    $zeroCheck `
    "Expected explicit_max_size == 0 guard in PageList"

# --- Summary ---
Write-Host ""
$total = $pass + $fail
Write-Host "Scrollback limit test: $pass PASS / $fail FAIL (total $total)" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
