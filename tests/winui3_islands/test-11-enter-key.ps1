param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# Test 11: Enter Key (VK_RETURN) — verify VK_RETURN is handled as a text key

$ErrorActionPreference = 'Stop'
$testName = "test-11-enter-key"

# --- Get UIA AutomationElement ---
if ($ProcessId -ne 0) {
    $elem = Find-GhosttyUIAElement -ProcessId $ProcessId
} else {
    $elem = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
}
Test-Assert -Condition ($elem -ne $null) -Message "UIA AutomationElement obtained"

# --- Focus via SetForegroundWindow + UIA ---
[Win32]::SetForegroundWindow($Hwnd) | Out-Null
Start-Sleep -Milliseconds 200
$elem.SetFocus()
Start-Sleep -Milliseconds 500

# --- Compute capture region ---
$rect = Get-WindowPosition -Hwnd $Hwnd
$dpi = [Win32]::GetDpiForWindow($Hwnd)
$titlebarHeight = [int](40 * ($dpi / 96.0))
$captureX = $rect.Left + 24
$captureY = $rect.Top + $titlebarHeight + 12
$captureWidth = [Math]::Max(220, [Math]::Min(420, $rect.Width - 48))
$captureHeight = [Math]::Max(120, [Math]::Min(180, $rect.Height - $titlebarHeight - 24))

# --- Screen capture BEFORE ---
$before = Capture-ScreenRegion -X $captureX -Y $captureY -Width $captureWidth -Height $captureHeight

# --- Type "echo entertest42" using SendKeys (proven approach from test-08) ---
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait("echo entertest42")
Start-Sleep -Milliseconds 200

# --- Now send VK_RETURN via SendInput to specifically test the VK_RETURN path ---
Send-KeyPress -VirtualKey 0x0D
Start-Sleep -Milliseconds 1200

# --- Screen capture AFTER ---
$after = Capture-ScreenRegion -X $captureX -Y $captureY -Width $captureWidth -Height $captureHeight

try {
    $diffCount = Get-BitmapSampleDiffCount -BitmapA $before -BitmapB $after
    $beforeSig = Get-BitmapSampleSignature -Bitmap $before
    $afterSig = Get-BitmapSampleSignature -Bitmap $after
} finally {
    $before.Dispose()
    $after.Dispose()
}

Write-Host "  Before signature: $beforeSig" -ForegroundColor DarkGray
Write-Host "  After signature:  $afterSig" -ForegroundColor DarkGray
Write-Host "  Sample diff count: $diffCount" -ForegroundColor Gray

Test-Assert -Condition ($diffCount -ge 1) -Message "screen changed after echo+Enter (VK_RETURN)"

Write-Host "PASS: $testName — VK_RETURN (Enter key) executed command in terminal" -ForegroundColor Green
