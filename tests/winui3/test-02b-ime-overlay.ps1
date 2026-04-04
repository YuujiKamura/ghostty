param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# test-02b-ime-overlay  EVerify IME overlay HWND exists with correct styles.
# Pure Win32, no UIA needed.

$ErrorActionPreference = 'Stop'
$testName = "test-02b-ime-overlay"

$inputOverlay = [IntPtr]::Zero; for ($i=0; $i -lt 10; $i++) { $inputOverlay = Get-ChildWindowByClass -Hwnd $Hwnd -ClassName "GhosttyInputOverlay"; if ($inputOverlay -ne [IntPtr]::Zero) { break }; Start-Sleep -Milliseconds 500 }
Test-Assert -Condition ($inputOverlay -ne [IntPtr]::Zero) -Message "$testName - GhosttyInputOverlay child window exists"

$overlayRect = Get-WindowPosition -Hwnd $inputOverlay
Write-Host "  Input overlay HWND=0x$($inputOverlay.ToString('X')) size=$($overlayRect.Width)x$($overlayRect.Height)" -ForegroundColor Gray

Test-AssertInRange -Value $overlayRect.Width -Min 1 -Max 8 -Message "$testName - input overlay width in fallback-sized range"
Test-AssertInRange -Value $overlayRect.Height -Min 1 -Max 8 -Message "$testName - input overlay height in fallback-sized range"

# Verify WS_VISIBLE and WS_CHILD are set (input overlay must be a visible child)
$style = [Win32]::GetWindowLong($inputOverlay, [Win32]::GWL_STYLE)
$WS_CHILD = 0x40000000
$WS_VISIBLE = 0x10000000
Test-Assert -Condition (($style -band $WS_CHILD) -ne 0) -Message "$testName - input overlay has WS_CHILD"
Test-Assert -Condition (($style -band $WS_VISIBLE) -ne 0) -Message "$testName - input overlay has WS_VISIBLE"

# Verify WS_EX_TRANSPARENT (mouse events pass through)
$exStyle = [Win32]::GetWindowLong($inputOverlay, [Win32]::GWL_EXSTYLE)
$WS_EX_TRANSPARENT = 0x00000020
Test-Assert -Condition (($exStyle -band $WS_EX_TRANSPARENT) -ne 0) -Message "$testName - input overlay has WS_EX_TRANSPARENT"

Write-Host "PASS: $testName - IME input overlay exists with correct styles" -ForegroundColor Green
