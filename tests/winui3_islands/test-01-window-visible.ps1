param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# Test 1: Window Visible — ウィンドウ表示確認 (UIA version)

$ErrorActionPreference = 'Stop'
$testName = "test-01-window-visible"

# ============================================================
# 1. Obtain UIA AutomationElement
# ============================================================
if ($ProcessId -ne 0) {
    $elem = Find-GhosttyUIAElement -ProcessId $ProcessId
    # Also need HWND for Win32 style checks
    if ($Hwnd -eq [IntPtr]::Zero) {
        $Hwnd = [IntPtr]::new($elem.Current.NativeWindowHandle)
    }
} elseif ($Hwnd -ne [IntPtr]::Zero) {
    $elem = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
} else {
    throw "$testName FAIL: Must provide -Hwnd or -ProcessId"
}

Test-Assert -Condition ($elem -ne $null) -Message "UIA AutomationElement obtained"

# ============================================================
# 2. HWND is valid (non-zero)
# ============================================================
Test-Assert -Condition ($Hwnd -ne [IntPtr]::Zero) -Message "HWND is valid ($Hwnd)"

# ============================================================
# 3. UIA IsOffscreen = false (window is visible)
# ============================================================
$isOffscreen = $elem.Current.IsOffscreen
Test-Assert -Condition (-not $isOffscreen) -Message "UIA IsOffscreen = false (window visible)"

# ============================================================
# 4. UIA BoundingRectangle — width > 100, height > 100
# ============================================================
$bounds = $elem.Current.BoundingRectangle
$width  = [int]$bounds.Width
$height = [int]$bounds.Height
Test-Assert -Condition ($width -gt 100)  -Message "UIA BoundingRectangle width $width > 100"
Test-Assert -Condition ($height -gt 100) -Message "UIA BoundingRectangle height $height > 100"
Write-Host "  CHECK: Window size ${width}x${height}" -ForegroundColor Gray

# ============================================================
# 5. UIA Name — window title is non-empty
# ============================================================
$title = $elem.Current.Name
Test-Assert -Condition (-not [string]::IsNullOrWhiteSpace($title)) -Message "UIA Name (title) is non-empty: '$title'"

# ============================================================
# 6. Win32 style: WS_OVERLAPPEDWINDOW
# ============================================================
$GWL_STYLE = -16
$style = [Win32]::GetWindowLong($Hwnd, $GWL_STYLE)
$WS_OVERLAPPEDWINDOW = 0x00CF0000
Test-Assert -Condition (($style -band $WS_OVERLAPPEDWINDOW) -eq $WS_OVERLAPPEDWINDOW) `
    -Message "WS_OVERLAPPEDWINDOW present (style=0x$($style.ToString('X8')))"

# ============================================================
# 7. Win32 extended style: WS_EX_NOREDIRECTIONBITMAP
# ============================================================
$GWL_EXSTYLE = -20
$exStyle = [Win32]::GetWindowLong($Hwnd, $GWL_EXSTYLE)
$WS_EX_NOREDIRECTIONBITMAP = 0x00200000
Test-Assert -Condition (($exStyle -band $WS_EX_NOREDIRECTIONBITMAP) -eq $WS_EX_NOREDIRECTIONBITMAP) `
    -Message "WS_EX_NOREDIRECTIONBITMAP present (exStyle=0x$($exStyle.ToString('X8')))"

Write-Host "PASS: $testName — Window visible (UIA), styled correctly, ${width}x${height}, title='$title'" -ForegroundColor Green
