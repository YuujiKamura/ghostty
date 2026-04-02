param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# test-03-window-ops — Combined window operations:
#   move -> resize -> maximize -> restore -> minimize -> restore
# Uses UIA TransformPattern/WindowPattern with Win32 fallbacks.
# No mouse input.

$ErrorActionPreference = 'Stop'
$testName = "test-03-window-ops"
$tolerance = 30

# ============================================================
# Get UIA AutomationElement
# ============================================================
$elem = $null
if ($ProcessId -ne 0) {
    try {
        $elem = Find-GhosttyUIAElement -ProcessId $ProcessId -TimeoutMs 5000
        Write-Host "  UIA element found via PID $ProcessId" -ForegroundColor Gray
    } catch {
        Write-Host "  Find-GhosttyUIAElement failed: $_" -ForegroundColor Yellow
    }
}
if ($elem -eq $null -and $Hwnd -ne [IntPtr]::Zero) {
    try {
        $elem = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
        Write-Host "  UIA element found via HWND 0x$($Hwnd.ToString('X'))" -ForegroundColor Gray
    } catch {
        Write-Host "  AutomationElement.FromHandle failed: $_" -ForegroundColor Yellow
    }
}

# Ensure window starts in Normal state
[Win32]::ShowWindow($Hwnd, [Win32]::SW_RESTORE) | Out-Null
Start-Sleep -Milliseconds 300

# ============================================================
# SUB-TEST 1: Move
# ============================================================
Write-Host "  --- Sub-test: Move ---" -ForegroundColor Cyan
$dragDistance = 200

$transform = $null
$useTransform = $false
if ($elem -ne $null) {
    try {
        $transform = Get-UIATransformPattern -Element $elem
        if ($transform.Current.CanMove) {
            $useTransform = $true
        }
    } catch { }
}

if ($useTransform) {
    $rectBefore = $elem.Current.BoundingRectangle
    $xBefore = [int]$rectBefore.X
    $transform.Move($rectBefore.X + $dragDistance, $rectBefore.Y)
    Start-Sleep -Milliseconds 300

    if ($ProcessId -ne 0) {
        $elem = Find-GhosttyUIAElement -ProcessId $ProcessId -TimeoutMs 2000
    } else {
        $elem = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
    }
    $rectAfter = $elem.Current.BoundingRectangle
    $movedX = [int]$rectAfter.X - $xBefore
    Write-Host "  Moved ${movedX}px via TransformPattern" -ForegroundColor Gray
    Test-AssertInRange -Value $movedX -Min ($dragDistance - $tolerance) -Max ($dragDistance + $tolerance) `
        -Message "$testName/move - window moved ~${dragDistance}px horizontally (TransformPattern)"
} else {
    $rectBefore = [RECT]::new()
    [Win32]::GetWindowRect($Hwnd, [ref]$rectBefore) | Out-Null
    $xBefore = $rectBefore.Left
    [Win32]::MoveWindow($Hwnd, $xBefore + $dragDistance, $rectBefore.Top, $rectBefore.Width, $rectBefore.Height, $true) | Out-Null
    Start-Sleep -Milliseconds 300

    $rectAfter = [RECT]::new()
    [Win32]::GetWindowRect($Hwnd, [ref]$rectAfter) | Out-Null
    $movedX = $rectAfter.Left - $xBefore
    Write-Host "  Moved ${movedX}px via MoveWindow" -ForegroundColor Gray
    Test-AssertInRange -Value $movedX -Min ($dragDistance - $tolerance) -Max ($dragDistance + $tolerance) `
        -Message "$testName/move - window moved ~${dragDistance}px horizontally (MoveWindow)"
}

# ============================================================
# SUB-TEST 2: Resize
# ============================================================
Write-Host "  --- Sub-test: Resize ---" -ForegroundColor Cyan
$deltaW = 100
$deltaH = 80

$usedTransform = $false
if ($elem -ne $null) {
    $transform = $null
    try { $transform = Get-UIATransformPattern -Element $elem } catch { }

    if ($transform -ne $null -and $transform.Current.CanResize) {
        $rectBefore = $elem.Current.BoundingRectangle
        $origW = [int]$rectBefore.Width
        $origH = [int]$rectBefore.Height
        $transform.Resize($origW + $deltaW, $origH + $deltaH)
        Start-Sleep -Milliseconds 500

        $rectAfter = $elem.Current.BoundingRectangle
        $actualDW = [int]$rectAfter.Width - $origW
        $actualDH = [int]$rectAfter.Height - $origH
        Write-Host "  Resized dW=$actualDW dH=$actualDH via TransformPattern" -ForegroundColor Gray
        Test-AssertInRange -Value $actualDW -Min ($deltaW - $tolerance) -Max ($deltaW + $tolerance) `
            -Message "$testName/resize - width delta ~${deltaW}px"
        Test-AssertInRange -Value $actualDH -Min ($deltaH - $tolerance) -Max ($deltaH + $tolerance) `
            -Message "$testName/resize - height delta ~${deltaH}px"
        $usedTransform = $true
    }
}

if (-not $usedTransform) {
    $rect = [RECT]::new()
    [Win32]::GetWindowRect($Hwnd, [ref]$rect) | Out-Null
    $origW = $rect.Width
    $origH = $rect.Height
    $ok = [Win32]::MoveWindow($Hwnd, $rect.Left, $rect.Top, $origW + $deltaW, $origH + $deltaH, $true)
    Test-Assert -Condition $ok -Message "$testName/resize - MoveWindow succeeded"
    Start-Sleep -Milliseconds 500

    $rect2 = [RECT]::new()
    [Win32]::GetWindowRect($Hwnd, [ref]$rect2) | Out-Null
    $actualDW = $rect2.Width - $origW
    $actualDH = $rect2.Height - $origH
    Write-Host "  Resized dW=$actualDW dH=$actualDH via MoveWindow" -ForegroundColor Gray
    Test-AssertInRange -Value $actualDW -Min ($deltaW - $tolerance) -Max ($deltaW + $tolerance) `
        -Message "$testName/resize - width delta ~${deltaW}px"
    Test-AssertInRange -Value $actualDH -Min ($deltaH - $tolerance) -Max ($deltaH + $tolerance) `
        -Message "$testName/resize - height delta ~${deltaH}px"
}

# ============================================================
# SUB-TEST 3: Maximize
# ============================================================
Write-Host "  --- Sub-test: Maximize ---" -ForegroundColor Cyan

# Re-acquire element for WindowPattern
if ($ProcessId -ne 0) {
    try { $elem = Find-GhosttyUIAElement -ProcessId $ProcessId -TimeoutMs 2000 } catch { }
}

$wp = $null
try { $wp = Get-UIAWindowPattern -Element $elem } catch { }

if ($wp -ne $null) {
    $wp.SetWindowVisualState([System.Windows.Automation.WindowVisualState]::Maximized)
} else {
    [Win32]::ShowWindow($Hwnd, 3) | Out-Null  # SW_MAXIMIZE = 3
}
Start-Sleep -Milliseconds 500

$isMaximized = [Win32]::IsZoomed($Hwnd)
Test-Assert -Condition $isMaximized -Message "$testName/maximize - window is maximized"

# ============================================================
# SUB-TEST 4: Restore (from maximized)
# ============================================================
Write-Host "  --- Sub-test: Restore from maximize ---" -ForegroundColor Cyan

if ($wp -ne $null) {
    $wp.SetWindowVisualState([System.Windows.Automation.WindowVisualState]::Normal)
} else {
    [Win32]::ShowWindow($Hwnd, [Win32]::SW_RESTORE) | Out-Null
}
Start-Sleep -Milliseconds 500

$isNormal = -not [Win32]::IsZoomed($Hwnd)
Test-Assert -Condition $isNormal -Message "$testName/restore - window is normal (not maximized)"

# ============================================================
# SUB-TEST 5: Minimize
# ============================================================
Write-Host "  --- Sub-test: Minimize ---" -ForegroundColor Cyan

if ($wp -ne $null) {
    $wp.SetWindowVisualState([System.Windows.Automation.WindowVisualState]::Minimized)
} else {
    [Win32]::ShowWindow($Hwnd, [Win32]::SW_MINIMIZE) | Out-Null
}

Wait-Condition -TimeoutMs 3000 -Description "window minimized" -ScriptBlock {
    [Win32]::IsIconic($Hwnd)
}
Test-Assert -Condition ([Win32]::IsIconic($Hwnd)) -Message "$testName/minimize - window is minimized"

# ============================================================
# SUB-TEST 6: Restore (from minimized)
# ============================================================
Write-Host "  --- Sub-test: Restore from minimize ---" -ForegroundColor Cyan

[Win32]::ShowWindow($Hwnd, [Win32]::SW_RESTORE) | Out-Null

Wait-Condition -TimeoutMs 3000 -Description "window restored after minimize" -ScriptBlock {
    (-not [Win32]::IsIconic($Hwnd)) -and [Win32]::IsWindowVisible($Hwnd)
}
Test-Assert -Condition ((-not [Win32]::IsIconic($Hwnd)) -and [Win32]::IsWindowVisible($Hwnd)) `
    -Message "$testName/restore - window restored and visible"

Write-Host "PASS: $testName - All window operations (move/resize/maximize/restore/minimize/restore) succeeded" -ForegroundColor Green
