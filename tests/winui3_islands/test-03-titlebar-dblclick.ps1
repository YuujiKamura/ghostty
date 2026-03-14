param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# Test 3: Maximize/Restore via UIA WindowPattern (no mouse input)

$ErrorActionPreference = 'Stop'
$testName = "test-03-maximize-restore"

# 1. Get AutomationElement
if ($ProcessId -ne 0) {
    $element = Find-GhosttyUIAElement -ProcessId $ProcessId
} else {
    $element = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
}
Write-Host "  UIA element acquired: '$($element.Current.Name)'" -ForegroundColor DarkGray

# 2. Get WindowPattern
$wp = Get-UIAWindowPattern -Element $element
Write-Host "  WindowPattern acquired" -ForegroundColor DarkGray

# 3. Ensure window starts in Normal state
$state = $wp.Current.WindowVisualState
if ($state -eq [System.Windows.Automation.WindowVisualState]::Maximized) {
    Write-Host "  Window is maximized, restoring first..." -ForegroundColor Gray
    $wp.SetWindowVisualState([System.Windows.Automation.WindowVisualState]::Normal)
    Start-Sleep -Milliseconds 500
}

# Verify normal state
$state = $wp.Current.WindowVisualState
$isNormal = ($state -eq [System.Windows.Automation.WindowVisualState]::Normal)
if (-not $isNormal) {
    # Fallback: check via Win32
    $isNormal = -not [Win32]::IsZoomed($Hwnd)
}
Test-Assert -Condition $isNormal -Message "Window starts in Normal state"

# 4. Maximize
Write-Host "  Maximizing via WindowPattern..." -ForegroundColor Gray
$wp.SetWindowVisualState([System.Windows.Automation.WindowVisualState]::Maximized)
Start-Sleep -Milliseconds 500

$state = $wp.Current.WindowVisualState
$isMaximized = ($state -eq [System.Windows.Automation.WindowVisualState]::Maximized)
if (-not $isMaximized) {
    # Fallback: check via Win32
    $isMaximized = [Win32]::IsZoomed($Hwnd)
}
Test-Assert -Condition $isMaximized -Message "Window is Maximized after SetWindowVisualState(Maximized)"

# 5. Restore
Write-Host "  Restoring via WindowPattern..." -ForegroundColor Gray
$wp.SetWindowVisualState([System.Windows.Automation.WindowVisualState]::Normal)
Start-Sleep -Milliseconds 500

$state = $wp.Current.WindowVisualState
$isNormal = ($state -eq [System.Windows.Automation.WindowVisualState]::Normal)
if (-not $isNormal) {
    # Fallback: check via Win32
    $isNormal = -not [Win32]::IsZoomed($Hwnd)
}
Test-Assert -Condition $isNormal -Message "Window is Normal after SetWindowVisualState(Normal)"

Write-Host "PASS: $testName — Maximize/restore cycle via UIA WindowPattern works" -ForegroundColor Green
