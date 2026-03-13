param([IntPtr]$Hwnd)

# Test 9: IME — GhosttyInputOverlay の存在とスタイルを確認
# Note: ImmGetContext is per-thread and returns NULL cross-process.
# IME functionality is validated by the window's existence and styles.

$ErrorActionPreference = 'Stop'
$testName = "test-09-ime"

$inputOverlay = Get-ChildWindowByClass -Hwnd $Hwnd -ClassName "GhosttyInputOverlay"
Test-Assert -Condition ($inputOverlay -ne [IntPtr]::Zero) -Message "GhosttyInputOverlay child window exists"

$overlayRect = Get-WindowPosition -Hwnd $inputOverlay
Write-Host "  Input overlay HWND=0x$($inputOverlay.ToString('X')) size=$($overlayRect.Width)x$($overlayRect.Height)" -ForegroundColor Gray

Test-AssertInRange -Value $overlayRect.Width -Min 1 -Max 8 -Message "input overlay width stays in fallback-sized range"
Test-AssertInRange -Value $overlayRect.Height -Min 1 -Max 8 -Message "input overlay height stays in fallback-sized range"

# Verify WS_VISIBLE and WS_CHILD are set (input overlay must be a visible child)
$style = [Win32]::GetWindowLong($inputOverlay, [Win32]::GWL_STYLE)
$WS_CHILD = 0x40000000
$WS_VISIBLE = 0x10000000
Test-Assert -Condition (($style -band $WS_CHILD) -ne 0) -Message "input overlay has WS_CHILD"
Test-Assert -Condition (($style -band $WS_VISIBLE) -ne 0) -Message "input overlay has WS_VISIBLE"

# Verify WS_EX_TRANSPARENT (mouse events pass through)
$exStyle = [Win32]::GetWindowLong($inputOverlay, [Win32]::GWL_EXSTYLE)
$WS_EX_TRANSPARENT = 0x00000020
Test-Assert -Condition (($exStyle -band $WS_EX_TRANSPARENT) -ne 0) -Message "input overlay has WS_EX_TRANSPARENT"

Write-Host "PASS: $testName — IME input overlay exists with correct styles" -ForegroundColor Green
