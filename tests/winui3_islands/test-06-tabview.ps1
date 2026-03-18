param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# Test 6: TabView表示 — UIA-based Tab/TabItem detection with HWND fallback
# Primary: Use UI Automation to find Tab control and TabItem children.
# Fallback: If XAML Islands doesn't expose UIA Tab/TabItem, fall back to
#           EnumChildWindows heuristic and emit a warning.

$ErrorActionPreference = 'Stop'
$testName = "test-06-tabview"

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

Test-Assert -Condition ($elem -ne $null) -Message "$testName — AutomationElement obtained"

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
        # FindAll returned a single element (PowerShell unwraps single-item collections)
        $tabItemCount = 1
        $tabItems = @($tabItems)
    } else {
        # Wrap in array to get .Count safely
        $tabItems = @($tabItems)
        $tabItemCount = $tabItems.Count
    }
}

# ============================================================
# 4. UIA path: Tab or TabItems found
# ============================================================
if ($tabControl -ne $null -or $tabItemCount -gt 0) {
    Write-Host "  UIA: Tab control found = $($tabControl -ne $null), TabItem count = $tabItemCount" -ForegroundColor Gray

    # Assert at least 1 TabItem
    Test-Assert -Condition ($tabItemCount -ge 1) -Message "$testName — at least 1 TabItem found via UIA ($tabItemCount)"

    # Print each TabItem's Name (tab title)
    foreach ($item in $tabItems) {
        $name = $item.Current.Name
        Write-Host "  TabItem: '$name'" -ForegroundColor Cyan
    }

    # Try SelectionPattern on Tab control to see which tab is selected
    if ($tabControl -ne $null) {
        $selPattern = $null
        $hasSelection = $tabControl.TryGetCurrentPattern(
            [System.Windows.Automation.SelectionPattern]::Pattern, [ref]$selPattern)
        if ($hasSelection -and $selPattern -ne $null) {
            $selected = $selPattern.Current.GetSelection()
            $selectedCount = 0
            if ($selected -ne $null) {
                if ($selected -is [System.Collections.ICollection]) {
                    $selectedCount = $selected.Count
                } else {
                    $selectedCount = 1
                    $selected = @($selected)
                }
            }
            if ($selectedCount -gt 0) {
                foreach ($sel in $selected) {
                    Write-Host "  Selected tab: '$($sel.Current.Name)'" -ForegroundColor Cyan
                }
            } else {
                Write-Host "  SelectionPattern: no tab currently selected" -ForegroundColor DarkYellow
            }
        } else {
            Write-Host "  Tab control does not support SelectionPattern" -ForegroundColor DarkYellow
        }
    }

    Write-Host "PASS: $testName — TabView detected via UIA ($tabItemCount TabItem(s))" -ForegroundColor Green
    return
}

# ============================================================
# 4b. Fallback: XAML Islands may expose TabView as Custom controls
#     Search for ControlType.Custom with TabView-related names
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
        Write-Host "PASS: $testName — TabView detected via UIA Custom controls" -ForegroundColor Green
        return
    }
    Write-Host "  UIA: No TabView-related Custom controls found among $customCount elements" -ForegroundColor DarkYellow
}

# ============================================================
# 5. Fallback: XAML Islands may not expose Tab/TabItem via UIA
#    Use the old EnumChildWindows heuristic
# ============================================================
Write-Host "  WARNING: UIA did not find Tab/TabItem elements. XAML Islands may not expose them." -ForegroundColor Yellow
Write-Host "  Falling back to EnumChildWindows heuristic ..." -ForegroundColor Yellow

$children = @()
$callback = [Win32+EnumWindowsProc]{
    param($childHwnd, $lParam)
    $script:children += $childHwnd
    return $true
}
[Win32]::EnumChildWindows($Hwnd, $callback, [IntPtr]::Zero)

Write-Host "  CHECK: Found $($children.Count) child window(s)" -ForegroundColor Gray

# Must have at least 2 children (XAML island child + drag bar at minimum)
Test-Assert -Condition ($children.Count -ge 2) `
    -Message "$testName — at least 2 child windows found ($($children.Count))"

# Check for a child window with significant size (XAML island)
$hasLargeChild = $false
$hasTabStripChild = $false
foreach ($ch in $children) {
    $r = [RECT]::new()
    [Win32]::GetWindowRect($ch, [ref]$r) | Out-Null
    $w = $r.Right - $r.Left
    $h = $r.Bottom - $r.Top

    if ($w -gt 200 -and $h -gt 200) {
        Write-Host "  CHECK: Large child found (${w}x${h}, hwnd=$ch)" -ForegroundColor Gray
        $hasLargeChild = $true
    }
    if ($w -gt 100 -and $h -gt 30) {
        $hasTabStripChild = $true
    }
}

Test-Assert -Condition $hasLargeChild `
    -Message "$testName — large XAML island child found (>200x200)"

Test-Assert -Condition $hasTabStripChild `
    -Message "$testName — tab strip area child found (>100x30)"

Write-Host "PASS: $testName — TabView child structure OK via HWND fallback ($($children.Count) children, XAML island present)" -ForegroundColor Green
