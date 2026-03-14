param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# Test 8: Keyboard Input — UIA SetFocus + SendKeys, screen capture diff

$ErrorActionPreference = 'Stop'
$testName = "test-08-keyboard-input"

# --- Get UIA AutomationElement ---
if ($ProcessId -ne 0) {
    $elem = Find-GhosttyUIAElement -ProcessId $ProcessId
} else {
    $elem = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
}
Test-Assert -Condition ($elem -ne $null) -Message "UIA AutomationElement obtained"

# --- Focus via UIA ---
$elem.SetFocus()
Start-Sleep -Milliseconds 500

# --- Load System.Windows.Forms for SendKeys ---
Add-Type -AssemblyName System.Windows.Forms

# --- Compute capture region ---
$rect = Get-WindowPosition -Hwnd $Hwnd
$dpi = [Win32]::GetDpiForWindow($Hwnd)
$titlebarHeight = [int](40 * ($dpi / 96.0))
$captureX = $rect.Left + 24
$captureY = $rect.Top + $titlebarHeight + 12
$captureWidth = [Math]::Max(220, [Math]::Min(420, $rect.Width - 48))
$captureHeight = [Math]::Max(120, [Math]::Min(180, $rect.Height - $titlebarHeight - 24))

# --- Screen capture BEFORE typing ---
$before = Capture-ScreenRegion -X $captureX -Y $captureY -Width $captureWidth -Height $captureHeight

# --- Send keyboard input via SendKeys ---
[System.Windows.Forms.SendKeys]::SendWait("echo codex-kb-test-96{ENTER}")
Start-Sleep -Milliseconds 1200

# --- Screen capture AFTER typing ---
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

Test-Assert -Condition ($diffCount -ge 1) -Message "client capture changed after keyboard input"

Write-Host "PASS: $testName — Keyboard input changed the terminal rendering" -ForegroundColor Green
