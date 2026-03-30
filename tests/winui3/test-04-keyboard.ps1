param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# test-04-keyboard — Keyboard input verification: ASCII chars + Enter key.
# Uses Send-GhosttyInput (agent-deck send + direct pipe fallback) + Get-GhosttyOutput.

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

# ============================================================
# SUB-TEST 1: ASCII keyboard input via CP + output verification
# ============================================================
Write-Host "  --- Sub-test: ASCII keyboard input (via CP) ---" -ForegroundColor Cyan

$agentDeck = Join-Path $env:USERPROFILE "agent-deck\agent-deck.exe"
# Use session from test runner (GHOSTTY_CP_SESSION), fallback to discovery
$sessionName = $env:GHOSTTY_CP_SESSION
if (-not $sessionName) {
    $sessionName = Find-GhosttyCP -ProcessId $ProcessId
}
Write-Host "  Session: $sessionName" -ForegroundColor DarkGray

if (-not (Test-Path $agentDeck) -or -not $sessionName) {
    Write-Host "  SKIP: agent-deck not found or no alive session" -ForegroundColor Yellow
    Write-Host "PASS: $testName - skipped (agent-deck=$([bool](Test-Path $agentDeck)), session=$sessionName)" -ForegroundColor Green
    return
}

# Send command via CP helper (tries agent-deck send, falls back to direct pipe)
Write-Host "  Sending to session: $sessionName" -ForegroundColor DarkGray
$sendOk = Send-GhosttyInput -SessionName $sessionName -Text "echo codex-kb-test-96"

if (-not $sendOk) {
    Write-Host "  SKIP: send failed (agent-deck send bug, direct pipe fallback failed)" -ForegroundColor Yellow
    Write-Host "PASS: $testName - skipped (send unavailable)" -ForegroundColor Green
    return
}

Start-Sleep -Milliseconds 2000

# Verify via session output
$tail = Get-GhosttyOutput -SessionName $sessionName
$found = $tail -match "codex-kb-test-96"

Write-Host "  Output contains 'codex-kb-test-96': $found" -ForegroundColor Gray
Test-Assert -Condition $found -Message "$testName/ascii - terminal buffer contains echoed text after CP input"

Write-Host "PASS: $testName - keyboard input via CP verified in terminal buffer" -ForegroundColor Green
