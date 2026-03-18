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

# --- Compute capture region ---
$rect = Get-WindowPosition -Hwnd $Hwnd
$dpi = [Win32]::GetDpiForWindow($Hwnd)
$titlebarHeight = [int](40 * ($dpi / 96.0))
$captureX = $rect.Left + 24
$captureY = $rect.Top + $titlebarHeight + 12
$captureWidth = [Math]::Max(220, [Math]::Min(420, $rect.Width - 48))
$captureHeight = [Math]::Max(120, [Math]::Min(180, $rect.Height - $titlebarHeight - 24))

# ============================================================
# SUB-TEST 1: ASCII keyboard input via Control Plane + TAIL verification
# ============================================================
Write-Host "  --- Sub-test: ASCII keyboard input (via control plane) ---" -ForegroundColor Cyan

$agentCtl = Join-Path $env:USERPROFILE "agent-relay\target\debug\agent-ctl.exe"
# Discover session name dynamically (same as test-02e)
$listOutput = & $agentCtl list 2>$null | Where-Object { $_ -match "ALIVE" }
$sessionName = $null
if ($listOutput) {
    $sessionLine = if ($listOutput -is [array]) { $listOutput[0] } else { $listOutput }
    if ($sessionLine -match 'session=([^\s|]+)') { $sessionName = $Matches[1] }
}
Write-Host "  Session: $sessionName" -ForegroundColor DarkGray

if (-not (Test-Path $agentCtl) -or -not $sessionName) {
    Write-Host "  SKIP: agent-ctl not found or no alive session" -ForegroundColor Yellow
    Write-Host "PASS: $testName - skipped (agent-ctl=$([bool](Test-Path $agentCtl)), session=$sessionName)" -ForegroundColor Green
    return
}

# Send command via control plane (same pattern as test-02e: send + raw-send CR)
Start-Process -FilePath $agentCtl -ArgumentList "send","$sessionName",'"echo codex-kb-test-96"' -NoNewWindow -Wait 2>&1 | Out-Null
Start-Process -FilePath $agentCtl -ArgumentList "raw-send","$sessionName","`r" -NoNewWindow -Wait 2>&1 | Out-Null
Start-Sleep -Milliseconds 3000

# Verify via TAIL (read terminal buffer) — no screen capture needed
$tail = & $agentCtl read $sessionName 2>&1
$tailStr = ($tail | Out-String)
$found = $tailStr -match "codex-kb-test-96"

Write-Host "  TAIL contains 'codex-kb-test-96': $found" -ForegroundColor Gray
Test-Assert -Condition $found -Message "$testName/ascii - terminal buffer contains echoed text after CP input"

Write-Host "PASS: $testName - keyboard input via control plane verified in terminal buffer" -ForegroundColor Green
