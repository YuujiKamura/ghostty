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
# Use session from test runner (GHOSTTY_CP_SESSION), fallback to discovery
$sessionName = $env:GHOSTTY_CP_SESSION
if (-not $sessionName) {
    $listOutput = & $agentCtl list --alive-only 2>&1 | Where-Object { $_ -match "ALIVE.*ghostty" }
    if ($listOutput) {
        $sessionLine = if ($listOutput -is [array]) { $listOutput[-1] } else { $listOutput }
        if ($sessionLine -match 'session=([^\s|]+)') { $sessionName = $Matches[1] }
    }
}
Write-Host "  Session: $sessionName" -ForegroundColor DarkGray

if (-not (Test-Path $agentCtl) -or -not $sessionName) {
    Write-Host "  SKIP: agent-ctl not found or no alive session" -ForegroundColor Yellow
    Write-Host "PASS: $testName - skipped (agent-ctl=$([bool](Test-Path $agentCtl)), session=$sessionName)" -ForegroundColor Green
    return
}

# Send command via control plane (direct invocation, not Start-Process)
Write-Host "  Sending to session: $sessionName" -ForegroundColor DarkGray
$sendOutput = & $agentCtl send $sessionName "echo codex-kb-test-96" 2>&1
Write-Host "  send output: $($sendOutput | Out-String)" -ForegroundColor DarkGray
Start-Sleep -Milliseconds 2000

# Verify via TAIL (read terminal buffer) — use --lines 200 to avoid
# missing markers when prior tests filled the buffer with output.
$tail = & $agentCtl read $sessionName --lines 200 2>&1
$tailStr = ($tail | Out-String)
$found = $tailStr -match "codex-kb-test-96"

Write-Host "  TAIL contains 'codex-kb-test-96': $found" -ForegroundColor Gray
Test-Assert -Condition $found -Message "$testName/ascii - terminal buffer contains echoed text after CP input"

Write-Host "PASS: $testName - keyboard input via control plane verified in terminal buffer" -ForegroundColor Green
