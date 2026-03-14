param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# Test 5: Caption Buttons — UIA経由で最小化/復元できること (マウスカーソル非占有)

$ErrorActionPreference = 'Stop'
$testName = "test-05-caption-buttons"

# --- Get UIA AutomationElement ---
if ($ProcessId -ne 0) {
    $elem = Find-GhosttyUIAElement -ProcessId $ProcessId
    Write-Host "  UIA element obtained via PID $ProcessId" -ForegroundColor DarkGray
} else {
    $elem = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
    Write-Host "  UIA element obtained via HWND 0x$($Hwnd.ToString('X'))" -ForegroundColor DarkGray
}

# --- Ensure window is restored before test ---
[Win32]::ShowWindow($Hwnd, [Win32]::SW_RESTORE) | Out-Null
Start-Sleep -Milliseconds 300

# --- Try to find Minimize button via UIA ---
$minimizeBtn = Find-UIAChild -Element $elem `
    -ControlType ([System.Windows.Automation.ControlType]::Button) `
    -Name "Minimize"

if ($minimizeBtn -eq $null) {
    # Try Japanese locale name
    $minimizeBtn = Find-UIAChild -Element $elem `
        -ControlType ([System.Windows.Automation.ControlType]::Button) `
        -Name "最小化"
}

if ($minimizeBtn -ne $null) {
    # --- Path A: UIA button found --- Invoke via InvokePattern ---
    Write-Host "  Found minimize button via UIA: '$($minimizeBtn.Current.Name)'" -ForegroundColor DarkGray
    Invoke-UIAButton -Button $minimizeBtn
} else {
    # --- Path B: Caption buttons are custom DWM-drawn (not XAML) ---
    # Fall back to WindowPattern.SetWindowVisualState(Minimized)
    Write-Host "  Minimize button not found via UIA; falling back to WindowPattern" -ForegroundColor DarkYellow
    $winPattern = Get-UIAWindowPattern -Element $elem
    $winPattern.SetWindowVisualState(
        [System.Windows.Automation.WindowVisualState]::Minimized)
}

# --- Verify minimized ---
Wait-Condition -TimeoutMs 3000 -Description "window minimized" -ScriptBlock {
    [Win32]::IsIconic($Hwnd)
}
Test-Assert -Condition ([Win32]::IsIconic($Hwnd)) -Message "window entered minimized state"

# --- Restore ---
[Win32]::ShowWindow($Hwnd, [Win32]::SW_RESTORE) | Out-Null

Wait-Condition -TimeoutMs 3000 -Description "window restored after minimize" -ScriptBlock {
    (-not [Win32]::IsIconic($Hwnd)) -and [Win32]::IsWindowVisible($Hwnd)
}
Test-Assert -Condition ((-not [Win32]::IsIconic($Hwnd)) -and [Win32]::IsWindowVisible($Hwnd)) -Message "window restored and visible"

Write-Host "PASS: $testName — Minimize via UIA succeeded and window restored" -ForegroundColor Green
