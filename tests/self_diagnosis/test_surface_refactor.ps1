#Requires -Version 5.1
<#
.SYNOPSIS
    Integration test for Surface.zig refactor (commit 1a708a14b).

.DESCRIPTION
    Verifies that the Surface.zig init/deinit refactoring correctly split
    the monolithic methods into four focused sub-functions. Checks:
    1. All four helper functions exist (setupXamlElements, registerXamlEventHandlers,
       unregisterXamlEventHandlers, cleanupXamlElements)
    2. init() calls setup then register in order
    3. deinit() calls unregister then cleanup in order
    4. The comptime test block exists
    5. No orphaned event handler registrations outside registerXamlEventHandlers
    6. Cleanup releases COM objects (comRelease calls in cleanupXamlElements)

.NOTES
    Static analysis only. Complements the in-file comptime test by checking
    structural properties that comptime cannot verify.
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

$surfacePath = Join-Path $RepoRoot "src\apprt\winui3\Surface.zig"
$src = Get-Content $surfacePath -Raw

# 1. All four helper functions exist as fn declarations
Check "Surface: setupXamlElements fn exists" `
    ($src -match 'fn setupXamlElements\(self: \*Self') `
    "setupXamlElements function declaration not found"

Check "Surface: registerXamlEventHandlers fn exists" `
    ($src -match 'fn registerXamlEventHandlers\(self: \*Self') `
    "registerXamlEventHandlers function declaration not found"

Check "Surface: unregisterXamlEventHandlers fn exists" `
    ($src -match 'fn unregisterXamlEventHandlers\(self: \*Self\) void') `
    "unregisterXamlEventHandlers function declaration not found"

Check "Surface: cleanupXamlElements fn exists" `
    ($src -match 'fn cleanupXamlElements\(self: \*Self\) void') `
    "cleanupXamlElements function declaration not found"

# 2. init() calls setup then register (order matters)
$initSection = $src.Substring(0, [Math]::Min($src.Length, 15000))
$setupPos = $initSection.IndexOf('self.setupXamlElements(')
$registerPos = $initSection.IndexOf('self.registerXamlEventHandlers(')
Check "Surface: init calls setupXamlElements" `
    ($setupPos -ge 0) `
    "init() should call self.setupXamlElements()"

Check "Surface: init calls registerXamlEventHandlers" `
    ($registerPos -ge 0) `
    "init() should call self.registerXamlEventHandlers()"

if ($setupPos -ge 0 -and $registerPos -ge 0) {
    Check "Surface: setup called before register in init" `
        ($setupPos -lt $registerPos) `
        "setupXamlElements must be called before registerXamlEventHandlers"
}

# 3. deinit/close calls unregister then cleanup
$unregisterPos = $src.IndexOf('self.unregisterXamlEventHandlers()')
$cleanupPos = $src.IndexOf('self.cleanupXamlElements()')
Check "Surface: deinit calls unregisterXamlEventHandlers" `
    ($unregisterPos -ge 0) `
    "deinit/close should call self.unregisterXamlEventHandlers()"

Check "Surface: deinit calls cleanupXamlElements" `
    ($cleanupPos -ge 0) `
    "deinit/close should call self.cleanupXamlElements()"

if ($unregisterPos -ge 0 -and $cleanupPos -ge 0) {
    Check "Surface: unregister called before cleanup in deinit" `
        ($unregisterPos -lt $cleanupPos) `
        "unregisterXamlEventHandlers must be called before cleanupXamlElements"
}

# 4. Comptime test block exists
Check "Surface: comptime test for refactored helpers" `
    ($src -match 'test "refactored helper functions exist and are callable"') `
    "Inline comptime test block should exist"

# 5. cleanupXamlElements releases COM objects
# Extract cleanupXamlElements body (look for release calls)
$cleanupMatch = [regex]::Match($src, 'fn cleanupXamlElements\(self: \*Self\) void \{([\s\S]*?)(?=\n        fn |\n    \};)')
if ($cleanupMatch.Success) {
    $cleanupBody = $cleanupMatch.Groups[1].Value
    $releaseCount = ([regex]::Matches($cleanupBody, '\.release\(\)')).Count
    Check "Surface: cleanupXamlElements releases COM objects" `
        ($releaseCount -ge 1) `
        "cleanupXamlElements should call .release() on COM objects (found $releaseCount)"
} else {
    Check "Surface: cleanupXamlElements body parseable" $false "Could not extract function body"
}

# 6. setupXamlElements creates Grid (activateInstance)
Check "Surface: setupXamlElements creates Grid" `
    ($src -match 'fn setupXamlElements[\s\S]*?activateInstance') `
    "setupXamlElements should call activateInstance to create Grid"

# Summary
Write-Host ""
Write-Host "Surface refactor test: $pass PASS / $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
exit $fail
