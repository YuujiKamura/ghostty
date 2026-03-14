param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# Test 2: Titlebar Drag — UIA TransformPattern or Win32 MoveWindow (no mouse ops)

$ErrorActionPreference = 'Stop'
$testName = "test-02-titlebar-drag"
$dragDistance = 200
$tolerance = 30

# 1. Get AutomationElement
if ($ProcessId -ne 0) {
    Write-Host "  Getting UIA element via PID $ProcessId ..." -ForegroundColor Gray
    $uiaElement = Find-GhosttyUIAElement -ProcessId $ProcessId
} else {
    Write-Host "  Getting UIA element via HWND 0x$($Hwnd.ToString('X')) ..." -ForegroundColor Gray
    $uiaElement = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
}

# 2. Try TransformPattern
$transform = $null
$useTransform = $false
try {
    $transform = Get-UIATransformPattern -Element $uiaElement
    if ($transform.Current.CanMove) {
        $useTransform = $true
        Write-Host "  TransformPattern available, CanMove=True" -ForegroundColor Gray
    } else {
        Write-Host "  TransformPattern available but CanMove=False, falling back to MoveWindow" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  TransformPattern not supported, falling back to MoveWindow" -ForegroundColor Yellow
}

if ($useTransform) {
    # --- Path A: UIA TransformPattern.Move ---
    $rectBefore = $uiaElement.Current.BoundingRectangle
    $xBefore = [int]$rectBefore.X
    $yBefore = [int]$rectBefore.Y
    Write-Host "  Before: X=$xBefore, Y=$yBefore" -ForegroundColor Gray

    $transform.Move($rectBefore.X + $dragDistance, $rectBefore.Y)
    Start-Sleep -Milliseconds 300

    # Re-fetch the element to get updated BoundingRectangle
    if ($ProcessId -ne 0) {
        $uiaElement = Find-GhosttyUIAElement -ProcessId $ProcessId -TimeoutMs 2000
    } else {
        $uiaElement = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
    }
    $rectAfter = $uiaElement.Current.BoundingRectangle
    $xAfter = [int]$rectAfter.X
    $movedX = $xAfter - $xBefore

    Write-Host "  After:  X=$xAfter (moved ${movedX}px)" -ForegroundColor Gray

    Test-AssertInRange -Value $movedX -Min ($dragDistance - $tolerance) -Max ($dragDistance + $tolerance) `
        -Message "$testName — TransformPattern moved window horizontally ~${dragDistance}px"
} else {
    # --- Path B: Win32 MoveWindow fallback ---
    $rectBefore = [RECT]::new()
    [Win32]::GetWindowRect($Hwnd, [ref]$rectBefore) | Out-Null
    $xBefore = $rectBefore.Left
    $yBefore = $rectBefore.Top
    $w = $rectBefore.Width
    $h = $rectBefore.Height
    Write-Host "  Before: X=$xBefore, Y=$yBefore, W=$w, H=$h" -ForegroundColor Gray

    [Win32]::MoveWindow($Hwnd, $xBefore + $dragDistance, $yBefore, $w, $h, $true) | Out-Null
    Start-Sleep -Milliseconds 300

    $rectAfter = [RECT]::new()
    [Win32]::GetWindowRect($Hwnd, [ref]$rectAfter) | Out-Null
    $xAfter = $rectAfter.Left
    $movedX = $xAfter - $xBefore

    Write-Host "  After:  X=$xAfter (moved ${movedX}px)" -ForegroundColor Gray

    Test-AssertInRange -Value $movedX -Min ($dragDistance - $tolerance) -Max ($dragDistance + $tolerance) `
        -Message "$testName — MoveWindow moved window horizontally ~${dragDistance}px"
}

Write-Host "PASS: $testName — Window moved ${movedX}px horizontally (no mouse operations)" -ForegroundColor Green
