#Requires -Version 5.1
<#
.SYNOPSIS
    Static analysis test: verify PointerDeviceType is used in Surface.zig
    to distinguish touch/pen/mouse events (Issue #134).

.DESCRIPTION
    Checks that:
    1. IPointerPoint vtable has get_PointerDeviceType slot in com_native.zig
    2. Surface.zig has a getPointerDeviceType helper function
    3. Surface.zig has a touch_anchor field for touch-drag scrolling
    4. getPointerDeviceType() is called in pressed/moved/released handlers
    5. Touch branch (device_type == 0) exists in all three handlers
    6. ContactRect accessor exists for future touch precision
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
$comNative = Get-Content (Join-Path $RepoRoot "src\apprt\winui3\com_native.zig") -Raw
$surface = Get-Content (Join-Path $RepoRoot "src\apprt\winui3\Surface.zig") -Raw

# 1. IPointerPoint vtable has get_PointerDeviceType slot
Check "com_native: IPointerPoint vtable get_PointerDeviceType" `
    ($comNative -match 'get_PointerDeviceType:\s*\*const fn') `
    "IPointerPoint VTable should have get_PointerDeviceType slot"

# 2. Surface has getPointerDeviceType helper function
Check "Surface: getPointerDeviceType helper" `
    ($surface -match 'fn getPointerDeviceType\(') `
    "Surface should have getPointerDeviceType() helper function"

# 3. Surface has touch_anchor field
Check "Surface: touch_anchor field" `
    ($surface -match 'touch_anchor:\s*\?com\.Point') `
    "Surface should have touch_anchor: ?com.Point field"

# 4. getPointerDeviceType is called in pointer handlers
$deviceTypeCallCount = ([regex]::Matches($surface, 'getPointerDeviceType\(point\)')).Count
Check "Surface: getPointerDeviceType() calls" `
    ($deviceTypeCallCount -ge 3) `
    "Expected >= 3 getPointerDeviceType() calls (pressed/moved/released), found $deviceTypeCallCount"

# 5. Touch branch exists (device_type == 0)
$touchBranchCount = ([regex]::Matches($surface, 'device_type == 0')).Count
Check "Surface: touch branches (device_type == 0)" `
    ($touchBranchCount -ge 3) `
    "Expected >= 3 touch branches, found $touchBranchCount"

# 6. ContactRect accessor exists for future touch precision
Check "com_native: IPointerPointProperties.ContactRect accessor" `
    ($comNative -match 'pub fn ContactRect\(self') `
    "IPointerPointProperties should have a ContactRect() method"

# Summary
Write-Host ""
Write-Host "Touch scroll test: $pass PASS / $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
exit $fail
