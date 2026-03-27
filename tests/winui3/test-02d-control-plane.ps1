param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# test-02d-control-plane — Verify control plane DLL responds via agent-deck.
# Requires: GHOSTTY_CONTROL_PLANE=1 env var on the shared ghostty process,
# and agent-deck built at ~/agent-deck/agent-deck.exe.

$ErrorActionPreference = 'Stop'
$testName = "test-02d-control-plane"

# Find agent-deck binary
$agentDeck = Join-Path $env:USERPROFILE "agent-deck\agent-deck.exe"
if (-not (Test-Path $agentDeck)) {
    Write-Host "SKIP: $testName — agent-deck.exe not found at $agentDeck" -ForegroundColor Yellow
    return
}

# Find alive ghostty session via agent-deck ls
$lsOutput = & $agentDeck ls --json 2>$null | ConvertFrom-Json
$cpSessions = @($lsOutput | Where-Object { $_.source -eq "ghostty" -and $_.pid -gt 0 })
if ($cpSessions.Count -eq 0) {
    Write-Host "SKIP: $testName — no alive ghostty CP session (is GHOSTTY_CONTROL_PLANE=1 set?)" -ForegroundColor Yellow
    return
}

$sessionName = $cpSessions[0].title
Write-Host "  Found session: $sessionName (pid=$($cpSessions[0].pid))" -ForegroundColor DarkGray

# Smoke test: session show (verifies PING + pipe connectivity)
$showOutput = & $agentDeck session show $sessionName --json 2>&1 | Out-String
$showExit = $LASTEXITCODE

$passChecks = 0
$failChecks = 0

# Check 1: session show succeeds
if ($showExit -eq 0 -and $showOutput -match '"status"') {
    $passChecks++
    Write-Host "  PING/SHOW ............... PASS" -ForegroundColor Green
} else {
    $failChecks++
    Write-Host "  PING/SHOW ............... FAIL" -ForegroundColor Red
}

# Check 2: send a marker and read it back
$marker = "cp-smoke-$(Get-Random -Minimum 1000 -Maximum 9999)"
& $agentDeck session send $sessionName "echo $marker" --no-wait 2>$null | Out-Null
Start-Sleep -Milliseconds 2000
$outputContent = & $agentDeck session output $sessionName -q 2>$null | Out-String

if ($outputContent -match $marker) {
    $passChecks++
    Write-Host "  SEND+READ ............... PASS" -ForegroundColor Green
} else {
    $failChecks++
    Write-Host "  SEND+READ ............... FAIL (marker '$marker' not found)" -ForegroundColor Red
}

Test-Assert -Condition ($failChecks -eq 0) -Message "$testName - agent-deck CP smoke passed ($passChecks checks, 0 failures)"
Write-Host "PASS: $testName - control plane responds to agent-deck (session=$sessionName)" -ForegroundColor Green
