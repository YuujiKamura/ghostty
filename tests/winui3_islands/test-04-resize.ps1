param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# Test 4: Resize — UIA TransformPattern or Win32 MoveWindow (no mouse input)

$ErrorActionPreference = 'Stop'
$testName = "test-04-resize"
$deltaW = 100
$deltaH = 80
$tolerance = 30

# 1. Get UIA AutomationElement
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

# 2. Try TransformPattern resize
$usedTransform = $false
if ($elem -ne $null) {
    $transform = $null
    try {
        $transform = Get-UIATransformPattern -Element $elem
    } catch {
        Write-Host "  TransformPattern not available: $_" -ForegroundColor Yellow
    }

    if ($transform -ne $null -and $transform.Current.CanResize) {
        Write-Host "  TransformPattern available, CanResize=True" -ForegroundColor Gray

        # Record before
        $rectBefore = $elem.Current.BoundingRectangle
        $origW = [int]$rectBefore.Width
        $origH = [int]$rectBefore.Height
        Write-Host "  Before: ${origW}x${origH}" -ForegroundColor Gray

        # Resize via TransformPattern
        $newW = $origW + $deltaW
        $newH = $origH + $deltaH
        Write-Host "  Calling Transform.Resize(${newW}, ${newH})..." -ForegroundColor Gray
        $transform.Resize($newW, $newH)
        Start-Sleep -Milliseconds 500

        # Record after (re-fetch element to get updated bounds)
        $rectAfter = $elem.Current.BoundingRectangle
        $afterW = [int]$rectAfter.Width
        $afterH = [int]$rectAfter.Height
        $actualDW = $afterW - $origW
        $actualDH = $afterH - $origH
        Write-Host "  After:  ${afterW}x${afterH} (dW=$actualDW, dH=$actualDH)" -ForegroundColor Gray

        Test-AssertInRange -Value $actualDW -Min ($deltaW - $tolerance) -Max ($deltaW + $tolerance) `
            -Message "$testName width delta ~${deltaW}px"
        Test-AssertInRange -Value $actualDH -Min ($deltaH - $tolerance) -Max ($deltaH + $tolerance) `
            -Message "$testName height delta ~${deltaH}px"

        $usedTransform = $true
    } else {
        $reason = if ($transform -eq $null) { "not supported" } else { "CanResize=False" }
        Write-Host "  TransformPattern $reason, falling back to MoveWindow" -ForegroundColor Yellow
    }
}

# 3. Fallback: Win32 MoveWindow (no mouse operations)
if (-not $usedTransform) {
    if ($Hwnd -eq [IntPtr]::Zero) {
        throw "$testName FAIL: No HWND available for MoveWindow fallback"
    }

    Write-Host "  Using Win32 MoveWindow fallback" -ForegroundColor Gray

    # Get current rect
    $rect = [RECT]::new()
    [Win32]::GetWindowRect($Hwnd, [ref]$rect) | Out-Null
    $origW = $rect.Right - $rect.Left
    $origH = $rect.Bottom - $rect.Top
    Write-Host "  Before: ${origW}x${origH} at ($($rect.Left), $($rect.Top))" -ForegroundColor Gray

    # Resize via MoveWindow
    $newW = $origW + $deltaW
    $newH = $origH + $deltaH
    Write-Host "  Calling MoveWindow($($rect.Left), $($rect.Top), ${newW}, ${newH})..." -ForegroundColor Gray
    $ok = [Win32]::MoveWindow($Hwnd, $rect.Left, $rect.Top, $newW, $newH, $true)
    Test-Assert -Condition $ok -Message "$testName MoveWindow succeeded"
    Start-Sleep -Milliseconds 500

    # Verify new size
    $rect2 = [RECT]::new()
    [Win32]::GetWindowRect($Hwnd, [ref]$rect2) | Out-Null
    $afterW = $rect2.Right - $rect2.Left
    $afterH = $rect2.Bottom - $rect2.Top
    $actualDW = $afterW - $origW
    $actualDH = $afterH - $origH
    Write-Host "  After:  ${afterW}x${afterH} (dW=$actualDW, dH=$actualDH)" -ForegroundColor Gray

    Test-AssertInRange -Value $actualDW -Min ($deltaW - $tolerance) -Max ($deltaW + $tolerance) `
        -Message "$testName width delta ~${deltaW}px"
    Test-AssertInRange -Value $actualDH -Min ($deltaH - $tolerance) -Max ($deltaH + $tolerance) `
        -Message "$testName height delta ~${deltaH}px"
}

$method = if ($usedTransform) { "TransformPattern" } else { "MoveWindow" }
Write-Host "PASS: $testName — Resize +${deltaW}x+${deltaH} via $method" -ForegroundColor Green
