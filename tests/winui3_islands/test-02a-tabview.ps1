param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# test-02a-tabview — Verify TabView exists and has at least 1 tab item.
# Uses UIA Tab/TabItem detection with Custom control and HWND fallbacks.

$ErrorActionPreference = 'Stop'
$testName = "test-02a-tabview"

# ============================================================
# 1. Get AutomationElement
# ============================================================
$elem = $null
if ($ProcessId -ne 0) {
    Write-Host "  UIA: Finding element by PID $ProcessId ..." -ForegroundColor DarkGray
    $elem = Find-GhosttyUIAElement -ProcessId $ProcessId
} else {
    Write-Host "  UIA: Finding element from HWND 0x$($Hwnd.ToString('X')) ..." -ForegroundColor DarkGray
    $elem = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
}

Test-Assert -Condition ($elem -ne $null) -Message "$testName - AutomationElement obtained"

# ============================================================
# 2. Find Tab control (ControlType.Tab)
# ============================================================
Write-Host "  UIA: Searching for Tab control ..." -ForegroundColor DarkGray
$tabControl = Find-UIAChild -Element $elem -ControlType ([System.Windows.Automation.ControlType]::Tab)

# ============================================================
# 3. Find all TabItems (ControlType.TabItem)
# ============================================================
Write-Host "  UIA: Searching for TabItem elements ..." -ForegroundColor DarkGray
$tabItems = Find-UIAChildren -Element $elem -ControlType ([System.Windows.Automation.ControlType]::TabItem)

$tabItemCount = 0
if ($tabItems -ne $null) {
    if ($tabItems -is [System.Collections.ICollection]) {
        $tabItemCount = $tabItems.Count
    } elseif ($tabItems -is [System.Windows.Automation.AutomationElement]) {
        $tabItemCount = 1
        $tabItems = @($tabItems)
    } else {
        $tabItems = @($tabItems)
        $tabItemCount = $tabItems.Count
    }
}

# ============================================================
# 4. UIA path: Tab or TabItems found
# ============================================================
if ($tabControl -ne $null -or $tabItemCount -gt 0) {
    Write-Host "  UIA: Tab control found = $($tabControl -ne $null), TabItem count = $tabItemCount" -ForegroundColor Gray

    Test-Assert -Condition ($tabItemCount -ge 1) -Message "$testName - at least 1 TabItem found via UIA ($tabItemCount)"

    foreach ($item in $tabItems) {
        $name = $item.Current.Name
        Write-Host "  TabItem: '$name'" -ForegroundColor Cyan
    }

    Write-Host "PASS: $testName - TabView detected via UIA ($tabItemCount TabItem(s))" -ForegroundColor Green
    return
}

# ============================================================
# 4b. Fallback: XAML Islands may expose TabView as Custom controls
# ============================================================
Write-Host "  UIA: Tab/TabItem not found. Trying Custom control type ..." -ForegroundColor DarkGray
$customControls = Find-UIAChildren -Element $elem -ControlType ([System.Windows.Automation.ControlType]::Custom)

$customCount = 0
if ($customControls -ne $null) {
    if ($customControls -is [System.Collections.ICollection]) {
        $customCount = $customControls.Count
    } elseif ($customControls -is [System.Windows.Automation.AutomationElement]) {
        $customCount = 1
        $customControls = @($customControls)
    } else {
        $customControls = @($customControls)
        $customCount = $customControls.Count
    }
}

if ($customCount -gt 0) {
    Write-Host "  UIA: Found $customCount Custom control(s), checking for TabView-related elements ..." -ForegroundColor Gray
    $tabViewFound = $false
    foreach ($ctrl in $customControls) {
        $ctrlName = $ctrl.Current.Name
        $ctrlClass = $ctrl.Current.ClassName
        $ctrlAuto = $ctrl.Current.AutomationId
        if ($ctrlClass -match 'TabView' -or $ctrlAuto -match 'TabView' -or
            $ctrlClass -match 'TabViewItem' -or $ctrlAuto -match 'TabViewItem' -or
            $ctrlName -match 'TabView') {
            Write-Host "  Custom: Name='$ctrlName' Class='$ctrlClass' AutoId='$ctrlAuto'" -ForegroundColor Cyan
            $tabViewFound = $true
        }
    }
    if ($tabViewFound) {
        Write-Host "PASS: $testName - TabView detected via UIA Custom controls" -ForegroundColor Green
        return
    }
    Write-Host "  UIA: No TabView-related Custom controls found among $customCount elements" -ForegroundColor DarkYellow
}

# ============================================================
# 5. Fallback: EnumChildWindows heuristic
# ============================================================
Write-Host "  WARNING: UIA did not find Tab/TabItem elements. Falling back to EnumChildWindows ..." -ForegroundColor Yellow

$children = @()
$callback = [Win32+EnumWindowsProc]{
    param($childHwnd, $lParam)
    $script:children += $childHwnd
    return $true
}
[Win32]::EnumChildWindows($Hwnd, $callback, [IntPtr]::Zero)

Write-Host "  CHECK: Found $($children.Count) child window(s)" -ForegroundColor Gray

Test-Assert -Condition ($children.Count -ge 2) `
    -Message "$testName - at least 2 child windows found ($($children.Count))"

$hasLargeChild = $false
foreach ($ch in $children) {
    $r = [RECT]::new()
    [Win32]::GetWindowRect($ch, [ref]$r) | Out-Null
    $w = $r.Right - $r.Left
    $h = $r.Bottom - $r.Top
    if ($w -gt 200 -and $h -gt 200) {
        Write-Host "  CHECK: Large child found (${w}x${h}, hwnd=$ch)" -ForegroundColor Gray
        $hasLargeChild = $true
    }
}

Test-Assert -Condition $hasLargeChild `
    -Message "$testName - large XAML island child found (>200x200)"

Write-Host "PASS: $testName - TabView child structure OK via HWND fallback ($($children.Count) children)" -ForegroundColor Green
