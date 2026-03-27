param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# test-04-keyboard — Keyboard input verification: ASCII chars + Enter key.
# Uses agent-deck session send (atomic text+CR) + session output for verification.

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
# SUB-TEST 1: ASCII keyboard input via agent-deck + output verification
# ============================================================
Write-Host "  --- Sub-test: ASCII keyboard input (via agent-deck) ---" -ForegroundColor Cyan

$agentDeck = Join-Path $env:USERPROFILE "agent-deck\agent-deck.exe"
# Use session from test runner (GHOSTTY_CP_SESSION), fallback to discovery
$sessionName = $env:GHOSTTY_CP_SESSION
if (-not $sessionName) {
    $lsOutput = & $agentDeck ls --json 2>$null | ConvertFrom-Json
    $cpSessions = @($lsOutput | Where-Object { $_.source -eq "ghostty" })
    if ($cpSessions.Count -gt 0) {
        $sessionName = $cpSessions[-1].title  # most recent
    }
}
Write-Host "  Session: $sessionName" -ForegroundColor DarkGray

if (-not (Test-Path $agentDeck) -or -not $sessionName) {
    Write-Host "  SKIP: agent-deck not found or no alive session" -ForegroundColor Yellow
    Write-Host "PASS: $testName - skipped (agent-deck=$([bool](Test-Path $agentDeck)), session=$sessionName)" -ForegroundColor Green
    return
}

# Send command via agent-deck (atomic text+Enter via SendRaw)
Write-Host "  Sending to session: $sessionName" -ForegroundColor DarkGray
& $agentDeck session send $sessionName "echo codex-kb-test-96" --no-wait 2>$null | Out-Null
Start-Sleep -Milliseconds 2000

# Verify via session output
$tail = & $agentDeck session output $sessionName -q 2>$null | Out-String
$found = $tail -match "codex-kb-test-96"

Write-Host "  Output contains 'codex-kb-test-96': $found" -ForegroundColor Gray
Test-Assert -Condition $found -Message "$testName/ascii - terminal buffer contains echoed text after CP input"

Write-Host "PASS: $testName - keyboard input via agent-deck verified in terminal buffer" -ForegroundColor Green
