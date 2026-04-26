param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# test-02c-drag-bar  EVerify drag bar HWND exists with correct DPI-scaled dimensions.
# Pure Win32, no UIA needed. Drag bar covers RIGHT portion only.

$ErrorActionPreference = 'Stop'
$testName = "test-02c-drag-bar"

# Add AdjustWindowRectExForDpi P/Invoke
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class DpiHelper {
    [DllImport("user32.dll")]
    public static extern bool AdjustWindowRectExForDpi(
        ref RECT2 lpRect, int dwStyle, bool bMenu, uint dwExStyle, uint dpi);
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
[DpiHelper]::AdjustWindowRectExForDpi([ref]$frame, [int]$style, $false, 0, $dpi) | Out-Null
$expectedDragBarHeight = -$frame.Top

$clientRect = Get-ClientPosition -Hwnd $Hwnd
$dragBar = Get-ChildWindowByClass -Hwnd $Hwnd -ClassName "GhosttyDragBar"

Test-AssertInRange -Value $dpi -Min 96 -Max 768 -Message "$testName - GetDpiForWindow returned a sane DPI"
Test-Assert -Condition ($dragBar -ne [IntPtr]::Zero) -Message "$testName - GhosttyDragBar child window exists"

$dragRect = Get-WindowPosition -Hwnd $dragBar
$windowRect = Get-WindowPosition -Hwnd $Hwnd

# Expected drag bar width.
#
# Implementation (src/apprt/winui3/nonclient_island_window.zig resizeDragBarWindow):
#     drag_width = client_width - tab_right_px - caption_buttons_w - border_w
# where:
#   caption_buttons_w = CAPTION_BUTTON_ZONE_96DPI(138) * scale
#   border_w          = SM_CXSIZEFRAME + SM_CXPADDEDBORDER (DPI-scaled)
#
# The drag bar's actual Left edge equals tab_right_px in client coords (it is a
# child of the parent window). So we can derive expectedDragW from the observed
# Left edge - this verifies the geometric invariant rather than re-running a
# stale model. Keep DRAG_ZONE_96DPI as a sanity floor for "is the drag area
# big enough to be useful?".
$DRAG_ZONE_96DPI = 538
$scale = $dpi / 96.0
$CAPTION_BUTTON_ZONE_96DPI = 138
$captionButtonsW = [int]($CAPTION_BUTTON_ZONE_96DPI * $scale)
$borderW = [int]([Math]::Round(8 * $scale))  # SM_CXSIZEFRAME + SM_CXPADDEDBORDER ~ 4+4 at 96 DPI

# Drag bar position relative to parent client area: dragRect.Left is in screen coords
# while clientRect.Left is the client area origin in screen coords. Use the offset.
$tabRightPx = $dragRect.Left - $windowRect.Left
$expectedDragW = $clientRect.Width - $tabRightPx - $captionButtonsW - $borderW
if ($expectedDragW -lt 0) { $expectedDragW = 0 }

# Sanity floor: drag bar must be wide enough to actually grab. Use DRAG_SPACE_96DPI scaled.
$DRAG_SPACE_96DPI = 400
$minUsableW = [int]($DRAG_SPACE_96DPI * $scale * 0.5)  # 50% of nominal drag space scaled

Write-Host "  DPI=$dpi scale=$scale expectedH=$expectedDragBarHeight expectedW=$expectedDragW (tabRight=$tabRightPx capBtns=$captionButtonsW border=$borderW) dragBar=$($dragRect.Width)x$($dragRect.Height) client=$($clientRect.Width)x$($clientRect.Height)" -ForegroundColor Gray

# Height tolerance: DPI-proportional with 6 px floor.
$heightTol = [int][Math]::Max(6, $expectedDragBarHeight * 0.10)
Test-AssertInRange -Value $dragRect.Height -Min ([Math]::Max(24, $expectedDragBarHeight - $heightTol)) -Max ($expectedDragBarHeight + $heightTol + 2) -Message "$testName - drag bar height matches AdjustWindowRectExForDpi frame top (+/- $heightTol)"

# Drag bar width: must be > 0, >= minUsableW, <= client width, and match geometric
# expected within DPI-proportional tolerance.
Test-Assert -Condition ($dragRect.Width -gt 0) -Message "$testName - drag bar width > 0"
Test-Assert -Condition ($dragRect.Width -ge $minUsableW) -Message "$testName - drag bar width >= $minUsableW px (usable drag space)"
Test-Assert -Condition ($dragRect.Width -le ($clientRect.Width + 8)) -Message "$testName - drag bar width does not exceed client width"
# DPI-proportional tolerance: 5% of expected width with 16 px floor.
# Fixed +/-16 px was too tight at high DPI (issue #233): at 200% scale a typical
# drag width is ~1000+ px and rounding/snap drift trivially exceeds 16 px. 5%
# scales with DPI; the floor preserves 96 DPI behaviour (5% of 320 = 16).
$tolerance = [int][Math]::Max(16, $expectedDragW * 0.05)
Test-AssertInRange -Value $dragRect.Width -Min ([Math]::Max(64, $expectedDragW - $tolerance)) -Max ($expectedDragW + $tolerance) -Message "$testName - drag bar width matches geometric formula (expected ~$expectedDragW +/- $tolerance)"

# Drag bar is positioned on the RIGHT side of the titlebar.
# Right edge tolerance: DPI-proportional (caption-button + border drift scales with DPI).
$dragRightEdge = $dragRect.Right
$windowRightEdge = $windowRect.Right
$rightEdgeTol = [int][Math]::Max(16, ($captionButtonsW + $borderW) * 0.10)
Test-AssertInRange -Value $dragRightEdge -Min ($windowRightEdge - $captionButtonsW - $borderW - $rightEdgeTol) -Max ($windowRightEdge + $rightEdgeTol) -Message "$testName - drag bar right edge near window right edge minus caption buttons (+/- $rightEdgeTol)"
Test-Assert -Condition ($dragRect.Left -gt $windowRect.Left) -Message "$testName - drag bar starts to the right of window left edge (tabs area uncovered)"

# Check drag bar extended styles
$dbExStyle = [Win32]::GetWindowLong($dragBar, [Win32]::GWL_EXSTYLE)
$WS_EX_LAYERED = 0x00080000
if (($dbExStyle -band $WS_EX_LAYERED) -ne 0) {
    Write-Host "  PASS: drag bar has WS_EX_LAYERED (exStyle=0x$($dbExStyle.ToString('X8')))" -ForegroundColor Green
} else {
    Write-Host "  WARN: drag bar missing WS_EX_LAYERED (exStyle=0x$($dbExStyle.ToString('X8')))  Emay work without it under NOREDIRECTIONBITMAP parent" -ForegroundColor Yellow
}

Write-Host "PASS: $testName - DPI and drag bar metrics are internally consistent" -ForegroundColor Green
