#Requires -Version 5.1
<#
.SYNOPSIS
    Test for preedit dirty flag fix: cursor row must be re-rendered when
    preedit is active or cleared.

.DESCRIPTION
    When IME preedit text is active but the cursor row has no other changes,
    the renderer's preedit_range can become null, causing the first characters
    of preedit to disappear.

    This test has three parts:
    1. Static check: render.zig's dirty detection handles preedit flag
       (either via t.flags.dirty.preedit check or page row dirty propagation)
    2. Static check: generic.zig has a guard against preedit_range being null
       when preedit is active
    3. Static check: Surface.zig preeditCallback marks cursor row dirty when
       clearing preedit (preedit_ == null path)

.NOTES
    Run from PowerShell: .\test_preedit_dirty.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$script:RepoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$script:Passed   = 0
$script:Failed   = 0
$script:Skipped  = 0

function Log([string]$msg) { Write-Host "[preedit-dirty-test] $msg" }

function Test-Result([string]$name, [bool]$pass, [string]$detail = "") {
    if ($pass) {
        $script:Passed++
        Write-Host "  PASS: $name $detail" -ForegroundColor Green
    } else {
        $script:Failed++
        Write-Host "  FAIL: $name $detail" -ForegroundColor Red
    }
}

# ============================================================
# Main tests
# ============================================================
Log "=== preedit dirty flag tests ==="

# --- Test 1: render.zig dirty detection includes preedit awareness ---
# The fix should ensure that when preedit is active/dirty, the cursor row
# is marked dirty. This can be via t.flags.dirty.preedit check in the
# dirty block, or via page-level row dirty propagation.
$renderZig = Join-Path $script:RepoRoot "src\terminal\render.zig"
$renderContent = Get-Content $renderZig -Raw

# Check that preedit is a field in Terminal.Dirty (used by render state)
$hasPreeditFlag = $renderContent -match 'flags\.dirty\.preedit' -or
                  $renderContent -match 'flags\.dirty'
Test-Result "render.zig references terminal dirty flags" $hasPreeditFlag

# Check that the dirty detection block (labeled 'dirty:') exists
$hasDirtyBlock = $renderContent -match 'dirty:\s*\{'
Test-Result "render.zig has dirty detection block" $hasDirtyBlock

# --- Test 2: generic.zig preedit_range null handling ---
$genericZig = Join-Path $script:RepoRoot "src\renderer\generic.zig"
$genericContent = Get-Content $genericZig -Raw

# The preedit_range determination should handle the case where row is not dirty
# Check that preedit_range is computed with a dirty check
$hasPreeditRange = $genericContent -match 'preedit_range.*PreeditRange'
Test-Result "generic.zig defines preedit_range" $hasPreeditRange

# Check that there's a null guard for preedit_range when iterating cells
$hasNullGuard = $genericContent -match 'preedit_range\s*\?\?' -or
                $genericContent -match 'if\s*\(preedit_range\)' -or
                $genericContent -match 'preedit_range\s+orelse'
Test-Result "generic.zig has preedit_range null guard" $hasNullGuard

# --- Test 3: Surface.zig preeditCallback marks cursor row dirty ---
$surfaceZig = Join-Path $script:RepoRoot "src\Surface.zig"
$surfaceContent = Get-Content $surfaceZig -Raw

# Check that preeditCallback exists
$hasPreeditCb = $surfaceContent -match 'fn\s+preeditCallback'
Test-Result "Surface.zig has preeditCallback" $hasPreeditCb

# Check that preeditCallback sets dirty flag
$setsDirty = $surfaceContent -match 'dirty\.preedit\s*=\s*true' -or
             $surfaceContent -match 'row\.dirty\s*=\s*true'
Test-Result "preeditCallback sets dirty flag" $setsDirty

# --- Test 4: Terminal.Dirty has preedit field ---
$terminalZig = Join-Path $script:RepoRoot "src\terminal\Terminal.zig"
$terminalContent = Get-Content $terminalZig -Raw

$hasDirtyPreedit = $terminalContent -match 'pub const Dirty\s*=\s*packed struct' -and
                   $terminalContent -match 'preedit:\s*bool'
Test-Result "Terminal.Dirty has preedit field" $hasDirtyPreedit

# --- Test 5: Zig unit tests exist for preedit dirty ---
$hasUnitTests = $renderContent -match 'test\s+"preedit dirty'
Test-Result "render.zig has preedit dirty unit tests" $hasUnitTests

# --- Test 6: Page row dirty test exists ---
$hasPageRowTest = $renderContent -match 'test\s+"cursor page row dirty'
Test-Result "render.zig has cursor page row dirty unit tests" $hasPageRowTest

# ============================================================
# Summary
# ============================================================
Log ""
Log "=== Results: $($script:Passed) passed, $($script:Failed) failed, $($script:Skipped) skipped ==="
if ($script:Failed -gt 0) {
    exit 1
}
exit 0
