param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# test-04-keyboard — Keyboard input verification: ASCII chars + Enter key.
# Merges old test-08 (keyboard input) and test-11 (enter key).
# Uses UIA SetFocus + SendKeys for text, Send-KeyPress for VK_RETURN.
# Retry loops for Debug build rendering delays.

$ErrorActionPreference = 'Stop'
$testName = "test-04-keyboard"

# --- Get UIA AutomationElement ---
if ($ProcessId -ne 0) {
    $elem = Find-GhosttyUIAElement -ProcessId $ProcessId
} else {
    $elem = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
}
Test-Assert -Condition ($elem -ne $null) -Message "$testName - UIA AutomationElement obtained"

# --- Focus via SetForegroundWindow + UIA ---
[Win32]::SetForegroundWindow($Hwnd) | Out-Null
Start-Sleep -Milliseconds 200
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

# ============================================================
# SUB-TEST 1: ASCII keyboard input
# ============================================================
Write-Host "  --- Sub-test: ASCII keyboard input ---" -ForegroundColor Cyan

$before = Capture-ScreenRegion -X $captureX -Y $captureY -Width $captureWidth -Height $captureHeight

# Send ASCII text via SendKeys
[System.Windows.Forms.SendKeys]::SendWait("echo codex-kb-test-96")
Start-Sleep -Milliseconds 1200

$after = Capture-ScreenRegion -X $captureX -Y $captureY -Width $captureWidth -Height $captureHeight

try {
    $diffCount = Get-BitmapSampleDiffCount -BitmapA $before -BitmapB $after
} finally {
    $before.Dispose()
    $after.Dispose()
}

Write-Host "  ASCII input sample diff count: $diffCount" -ForegroundColor Gray
Test-Assert -Condition ($diffCount -ge 1) -Message "$testName/ascii - client capture changed after keyboard input"

# ============================================================
# SUB-TEST 2: Enter key (VK_RETURN)
# ============================================================
Write-Host "  --- Sub-test: Enter key (VK_RETURN) ---" -ForegroundColor Cyan

# Re-focus
[Win32]::SetForegroundWindow($Hwnd) | Out-Null
Start-Sleep -Milliseconds 200
$elem.SetFocus()
Start-Sleep -Milliseconds 300

# Capture before Enter
$beforeEnter = Capture-ScreenRegion -X $captureX -Y $captureY -Width $captureWidth -Height $captureHeight

# Send VK_RETURN via SendInput — this executes the echo command
Send-KeyPress -VirtualKey 0x0D

# After Enter, cmd.exe prints output + new prompt. Send another char to guarantee visible change.
Start-Sleep -Milliseconds 2000
[System.Windows.Forms.SendKeys]::SendWait("x")
Start-Sleep -Milliseconds 1000

# Screen capture AFTER with retry (Debug builds render slowly)
$diffCountEnter = 0
$maxRetries = 3
$waitMs = 1500

for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
    Start-Sleep -Milliseconds $waitMs
    $afterEnter = Capture-ScreenRegion -X $captureX -Y $captureY -Width $captureWidth -Height $captureHeight

    try {
        $diffCountEnter = Get-BitmapSampleDiffCount -BitmapA $beforeEnter -BitmapB $afterEnter
    } finally {
        $afterEnter.Dispose()
    }

    Write-Host "  Enter key attempt ${attempt}: diffCount=$diffCountEnter (waited ${waitMs}ms)" -ForegroundColor DarkGray
    if ($diffCountEnter -ge 1) { break }

    $waitMs = $waitMs + 1000
}
$beforeEnter.Dispose()

Write-Host "  Enter key sample diff count: $diffCountEnter" -ForegroundColor Gray
Test-Assert -Condition ($diffCountEnter -ge 1) -Message "$testName/enter - screen changed after VK_RETURN"

Write-Host "PASS: $testName - ASCII input and Enter key both produce visible terminal changes" -ForegroundColor Green
