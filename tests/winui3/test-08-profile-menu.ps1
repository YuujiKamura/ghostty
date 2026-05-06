param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# test-08-profile-menu — Verify profile dropdown menu is populated with shell entries.
# Uses UIA to find the SplitButton and MenuFlyoutItem elements.

$ErrorActionPreference = 'Stop'
$testName = "test-08-profile-menu"

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
# 2. Find SplitButton by AutomationId="AddTabSplitButton"
#    (set via AutomationProperties.AutomationId in xaml/TabViewRoot.xaml)
# ============================================================
Write-Host "  UIA: Searching for SplitButton by AutomationId='AddTabSplitButton' ..." -ForegroundColor DarkGray

$splitButtonIdCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
    "AddTabSplitButton")
$splitButton = $elem.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $splitButtonIdCondition)

Test-Assert -Condition ($splitButton -ne $null) -Message "$testName - SplitButton found by AutomationId"
Write-Host "  SplitButton found: Name='$($splitButton.Current.Name)' AutomationId='$($splitButton.Current.AutomationId)'" -ForegroundColor Green

# ============================================================
# 3. Find MenuItem elements (ControlType.MenuItem) — profile entries
#    These are the MenuFlyoutItems populated by populateProfileMenu().
#    Note: MenuFlyoutItems may only be visible after expanding the flyout.
# ============================================================
Write-Host "  UIA: Searching for MenuItem elements (profile entries) ..." -ForegroundColor DarkGray

# Try to open the flyout via ExpandCollapse, Invoke, or secondary button click
$flyoutOpened = $false

# Method 1: ExpandCollapse pattern
try {
    $expandPattern = $splitButton.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
    if ($expandPattern -ne $null) {
        Write-Host "  UIA: Expanding SplitButton flyout via ExpandCollapse ..." -ForegroundColor DarkGray
        $expandPattern.Expand()
        $flyoutOpened = $true
        Start-Sleep -Milliseconds 800
    }
} catch {
    Write-Host "  UIA: ExpandCollapse not available" -ForegroundColor DarkGray
}

# Method 2: Find the secondary (dropdown arrow) button inside the SplitButton
if (-not $flyoutOpened) {
    Write-Host "  UIA: Looking for secondary dropdown button inside SplitButton ..." -ForegroundColor DarkGray
    $secondaryBtns = $splitButton.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Button
        ))
    )
    if ($secondaryBtns -ne $null -and $secondaryBtns.Count -gt 0) {
        # The last button in SplitButton is typically the dropdown arrow
        $dropdownBtn = $secondaryBtns[$secondaryBtns.Count - 1]
        Write-Host "    Found dropdown button: Name='$($dropdownBtn.Current.Name)' AutomationId='$($dropdownBtn.Current.AutomationId)'" -ForegroundColor DarkGray
        try {
            $invokePattern = $dropdownBtn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
            $invokePattern.Invoke()
            $flyoutOpened = $true
            Start-Sleep -Milliseconds 800
        } catch {
            Write-Host "    Could not invoke dropdown button" -ForegroundColor DarkGray
        }
    }
}

# Method 3: Try Invoke on the SplitButton itself
if (-not $flyoutOpened) {
    Write-Host "  UIA: Trying Invoke on SplitButton itself ..." -ForegroundColor DarkGray
    try {
        $invokePattern = $splitButton.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $invokePattern.Invoke()
        $flyoutOpened = $true
        Start-Sleep -Milliseconds 800
    } catch {
        Write-Host "    Invoke not supported on SplitButton" -ForegroundColor DarkGray
    }
}

Write-Host "  Flyout opened: $flyoutOpened" -ForegroundColor $(if ($flyoutOpened) { "Green" } else { "Yellow" })

# Search for MenuItems in the entire tree (flyout may be a popup window)
$menuItems = $null
$rootElement = [System.Windows.Automation.AutomationElement]::RootElement
$menuItemCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::MenuItem
)

# Search from root since flyouts are top-level popups
$menuItems = $rootElement.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    $menuItemCondition
)

$profileMenuItems = @()
Write-Host "  UIA: Total MenuItems found globally: $($menuItems.Count)" -ForegroundColor DarkGray
if ($menuItems -ne $null -and $menuItems.Count -gt 0) {
    foreach ($mi in $menuItems) {
        $miName = $mi.Current.Name
        $miPid = $mi.Current.ProcessId
        Write-Host "    MenuItem: '$miName' (PID=$miPid)" -ForegroundColor DarkGray
        # Filter to our process
        if ($ProcessId -ne 0 -and $miPid -ne $ProcessId) { continue }
        # Match known profile names
        if ($miName -match "Command Prompt|PowerShell|Git Bash|WSL") {
            $profileMenuItems += $mi
            Write-Host "    MATCH: '$miName'" -ForegroundColor Cyan
        }
    }
}

# Also search for Menu control type (flyout popup)
Write-Host "  UIA: Searching for Menu controls ..." -ForegroundColor DarkGray
$menuCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Menu
)
$menus = $rootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $menuCondition)
Write-Host "  UIA: Menu controls found: $($menus.Count)" -ForegroundColor DarkGray

# Search all popups (top-level windows) that belong to our process
Write-Host "  UIA: Searching for popup windows for PID $ProcessId ..." -ForegroundColor DarkGray
$allTopLevel = $rootElement.FindAll(
    [System.Windows.Automation.TreeScope]::Children,
    [System.Windows.Automation.Condition]::TrueCondition
)
foreach ($tl in $allTopLevel) {
    if ($tl.Current.ProcessId -eq $ProcessId -and $tl.Current.ClassName -ne 'GhosttyWindow') {
        Write-Host "    Popup: Class='$($tl.Current.ClassName)' Name='$($tl.Current.Name)'" -ForegroundColor Yellow
        # Search MenuItems inside this popup
        $popupMenuItems = $tl.FindAll(
            [System.Windows.Automation.TreeScope]::Descendants,
            $menuItemCondition
        )
        foreach ($pmi in $popupMenuItems) {
            $profileMenuItems += $pmi
            Write-Host "      PopupMenuItem: '$($pmi.Current.Name)'" -ForegroundColor Cyan
        }
    }
}

# Collapse flyout if we expanded it
if ($expandPattern -ne $null) {
    try { $expandPattern.Collapse() } catch {}
}

# ============================================================
# 4. Assertions
# ============================================================

# At minimum, "Command Prompt" must exist (always=true in profiles.zig)
$cmdPromptFound = $false
foreach ($item in $profileMenuItems) {
    if ($item.Current.Name -eq "Command Prompt") {
        $cmdPromptFound = $true
        break
    }
}

# Strict assertions — flyout must open and expose profile MenuFlyoutItems.
Test-Assert -Condition ($profileMenuItems.Count -ge 1) -Message "$testName - at least one MenuFlyoutItem visible"
Test-Assert -Condition $cmdPromptFound -Message "$testName - 'Command Prompt' profile found in menu"
Write-Host "  $testName PASSED: $($profileMenuItems.Count) profile(s) in dropdown" -ForegroundColor Green
