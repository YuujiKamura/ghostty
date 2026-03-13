param([IntPtr]$Hwnd)

# Test 10: DPI — GetDpiForWindow と drag bar 寸法の整合を確認
# WT方式: AdjustWindowRectExForDpi で -frame.top を算出

$ErrorActionPreference = 'Stop'
$testName = "test-10-dpi"

# Add AdjustWindowRectExForDpi P/Invoke
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class DpiHelper {
    [DllImport("user32.dll")]
    public static extern bool AdjustWindowRectExForDpi(
        ref RECT2 lpRect, uint dwStyle, bool bMenu, uint dwExStyle, uint dpi);
}

[StructLayout(LayoutKind.Sequential)]
public struct RECT2 {
    public int Left, Top, Right, Bottom;
}
"@ -ErrorAction SilentlyContinue

$dpi = [Win32]::GetDpiForWindow($Hwnd)

# WT: AdjustWindowRectExForDpi(&frame, style, FALSE, 0, dpi); expectedH = -frame.top
$style = [Win32]::GetWindowLong($Hwnd, [Win32]::GWL_STYLE)
$frame = New-Object RECT2
[DpiHelper]::AdjustWindowRectExForDpi([ref]$frame, [uint32]$style, $false, 0, $dpi) | Out-Null
$expectedDragBarHeight = -$frame.Top

$clientRect = Get-ClientPosition -Hwnd $Hwnd
$dragBar = Get-ChildWindowByClass -Hwnd $Hwnd -ClassName "GhosttyDragBar"

Test-AssertInRange -Value $dpi -Min 96 -Max 768 -Message "GetDpiForWindow returned a sane DPI"
Test-Assert -Condition ($dragBar -ne [IntPtr]::Zero) -Message "GhosttyDragBar child window exists"

$dragRect = Get-WindowPosition -Hwnd $dragBar
Write-Host "  DPI=$dpi expectedH=$expectedDragBarHeight dragBar=$($dragRect.Width)x$($dragRect.Height) client=$($clientRect.Width)x$($clientRect.Height)" -ForegroundColor Gray

Test-AssertInRange -Value $dragRect.Height -Min ([Math]::Max(24, $expectedDragBarHeight - 6)) -Max ($expectedDragBarHeight + 8) -Message "drag bar height matches AdjustWindowRectExForDpi frame top"
Test-AssertInRange -Value $dragRect.Width -Min ([Math]::Max(64, $clientRect.Width - 8)) -Max ($clientRect.Width + 8) -Message "drag bar width tracks client width"

# Check drag bar extended styles (WS_EX_LAYERED is ideal but may not be settable
# on all XAML Islands configurations — warn but don't fail)
$dbExStyle = [Win32]::GetWindowLong($dragBar, [Win32]::GWL_EXSTYLE)
$WS_EX_LAYERED = 0x00080000
if (($dbExStyle -band $WS_EX_LAYERED) -ne 0) {
    Write-Host "  PASS: drag bar has WS_EX_LAYERED (exStyle=0x$($dbExStyle.ToString('X8')))" -ForegroundColor Green
} else {
    Write-Host "  WARN: drag bar missing WS_EX_LAYERED (exStyle=0x$($dbExStyle.ToString('X8'))) — may work without it under NOREDIRECTIONBITMAP parent" -ForegroundColor Yellow
}

Write-Host "PASS: $testName — DPI and drag bar metrics are internally consistent" -ForegroundColor Green
