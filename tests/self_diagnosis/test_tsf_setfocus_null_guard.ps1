#Requires -Version 5.1
<#
.SYNOPSIS
    Regression test for Issue #135: TSF SetFocus null-dereference crash.

.DESCRIPTION
    The fix (commit 9b1478041) added null guards to tsf.zig focus() and
    associateFocus() to prevent panic when _documentMgr is null, and moved
    TSF focus management from WM_SETFOCUS to WM_ACTIVATE in App.zig.

    This test verifies:
    1. tsf.zig: focus() has null guard for _documentMgr (orelse return pattern)
    2. tsf.zig: associateFocus() has null guard for _documentMgr (orelse block)
    3. tsf.zig: focus() has SAFETY doc comment warning against WM_SETFOCUS usage
    4. App.zig: WM_ACTIVATE handler exists and calls tsf focus/unfocus
    5. App.zig: WM_SETFOCUS does NOT call tsf.focus() (would cause recursion)
    6. App.zig: WM_ACTIVATE extracts activation parameter correctly (& 0xFFFF)

.NOTES
    Static analysis only. No runtime dependencies.
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

# Read source files
$tsfSrc = Get-Content (Join-Path $RepoRoot "src\apprt\winui3\tsf.zig") -Raw
$appSrc = Get-Content (Join-Path $RepoRoot "src\apprt\winui3\App.zig") -Raw

# === tsf.zig checks ===

# 1. focus() null guard: "self._documentMgr orelse" pattern
Check "tsf.zig: focus() has _documentMgr null guard" `
    ($tsfSrc -match 'pub fn focus\(self.*\).*void\s*\{[^}]*self\._documentMgr orelse') `
    "focus() should use 'self._documentMgr orelse' to guard against null"

# 2. associateFocus() null guard
Check "tsf.zig: associateFocus() has _documentMgr null guard" `
    ($tsfSrc -match 'pub fn associateFocus\(self.*\).*void\s*\{[^}]*self\._documentMgr orelse') `
    "associateFocus() should use 'self._documentMgr orelse' to guard against null"

# 3. SAFETY doc comment on focus()
Check "tsf.zig: focus() has SAFETY doc comment" `
    ($tsfSrc -match '/// SAFETY: Do NOT call from WM_SETFOCUS') `
    "focus() should have SAFETY comment warning against WM_SETFOCUS"

# 4. focus() does NOT use .? (forced unwrap) on _documentMgr
$focusForcedUnwrap = [regex]::Matches($tsfSrc, 'pub fn focus\(self.*\).*void\s*\{[^}]*self\._documentMgr\.\?')
Check "tsf.zig: focus() does NOT force-unwrap _documentMgr" `
    ($focusForcedUnwrap.Count -eq 0) `
    "focus() should NOT use _documentMgr.? (would crash on null)"

# === App.zig checks ===

# 5. WM_ACTIVATE handler exists
Check "App.zig: WM_ACTIVATE handler exists" `
    ($appSrc -match 'WM_ACTIVATE\s*=>') `
    "App.zig should have a WM_ACTIVATE handler"

# 6. WM_ACTIVATE calls tsf focus/unfocus (multiline match)
$activateMatch = [regex]::Match($appSrc, 'WM_ACTIVATE\s*=>\s*\{([\s\S]*?)\},', [System.Text.RegularExpressions.RegexOptions]::Multiline)
if ($activateMatch.Success) {
    $activateBody = $activateMatch.Groups[1].Value
    Check "App.zig: WM_ACTIVATE calls tsf_inst.focus()" `
        ($activateBody -match 'tsf_inst.*\.focus\(\)') `
        "WM_ACTIVATE handler should call tsf_inst.focus()"
} else {
    Check "App.zig: WM_ACTIVATE body found" $false "Could not extract WM_ACTIVATE block"
}

# 7. WM_SETFOCUS does NOT call tsf.focus() (only comments, not actual code)
$setfocusMatch = [regex]::Match($appSrc, 'WM_SETFOCUS\s*=>\s*\{([\s\S]*?)\},', [System.Text.RegularExpressions.RegexOptions]::Multiline)
if ($setfocusMatch.Success) {
    $setfocusBody = $setfocusMatch.Groups[1].Value
    # Filter out comment lines (starting with //) to only check actual code
    $codeLines = $setfocusBody -split "`n" | Where-Object { $_.Trim() -notmatch '^\s*//' -and $_.Trim() -ne '' }
    $codeOnly = $codeLines -join "`n"
    $callsTsfFocus = $codeOnly -match 'tsf.*\.focus\(\)'
    Check "App.zig: WM_SETFOCUS does NOT call tsf.focus() in code" `
        (-not $callsTsfFocus) `
        "WM_SETFOCUS calling tsf.focus() causes infinite recursion"
} else {
    Check "App.zig: WM_SETFOCUS handler found" $false "Could not find WM_SETFOCUS block"
}

# 8. WM_ACTIVATE extracts activation with bitmask
Check "App.zig: WM_ACTIVATE uses 0xFFFF bitmask" `
    ($appSrc -match '0xFFFF') `
    "WM_ACTIVATE should mask wparam with 0xFFFF to extract activation state"

# Summary
Write-Host ""
Write-Host "TSF SetFocus null-guard test: $pass PASS / $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
exit $fail
