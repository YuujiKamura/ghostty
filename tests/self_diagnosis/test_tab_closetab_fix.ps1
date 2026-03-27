#Requires -Version 5.1
<#
.SYNOPSIS
    Verify closeTab uses COM indexOf (not stale indexOfScalar) (#129).

.DESCRIPTION
    Commit b7faab7d3 fixed closeTab to use the COM IVector.indexOf pattern
    instead of the removed indexOfScalar. This test ensures the correct
    pattern is used in event_handlers.zig.

.NOTES
    Static analysis only.
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

$eventHandlers = Join-Path $RepoRoot "src\apprt\winui3\event_handlers.zig"
Check "event_handlers.zig exists" (Test-Path $eventHandlers) "File not found"

$content = Get-Content $eventHandlers -Raw

# ================================================================
# 1. Uses COM indexOf (IVector pattern)
# ================================================================
Check "closeTab uses COM indexOf" `
    ($content -match 'indexOf\(@ptrCast') `
    "Should use COM IVector.indexOf with @ptrCast for tab lookup"

# ================================================================
# 2. No stale indexOfScalar usage for tab removal
# ================================================================
Check "No indexOfScalar for tab removal" `
    (-not ($content -match 'indexOfScalar.*tab')) `
    "indexOfScalar was the stale pattern — should be replaced by COM indexOf"

# ================================================================
# 3. closeTab function exists
# ================================================================
Check "closeTab function called" `
    ($content -match 'closeTab\(') `
    "event_handlers should call closeTab"

# ================================================================
# Summary
# ================================================================
Write-Host "`n--- Summary: $pass passed, $fail failed ---"
if ($fail -gt 0) { exit 1 }
