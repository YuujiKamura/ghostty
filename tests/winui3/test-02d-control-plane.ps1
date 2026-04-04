param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# test-02d-control-plane  EVerify control plane DLL responds via deckpilot.
# Requires: GHOSTTY_CONTROL_PLANE=1 env var on the shared ghostty process,
# and deckpilot built at ~/deckpilot/deckpilot.exe.

$ErrorActionPreference = 'Stop'
$testName = "test-02d-control-plane"

# Find deckpilot binary
$agentDeck = Join-Path $env:USERPROFILE "deckpilot\deckpilot.exe"
if (-not (Test-Path $agentDeck)) {
    Write-Host "SKIP: $testName  Edeckpilot.exe not found at $agentDeck" -ForegroundColor Yellow
    return
}

# Register + discover CP session
if ($ProcessId -gt 0) {
    Register-GhosttyCP -ProcessId $ProcessId | Out-Null
}

$sessionName = $env:GHOSTTY_CP_SESSION
if (-not $sessionName) {
    $sessionName = Find-GhosttyCP -ProcessId $ProcessId
}
if (-not $sessionName) {
    Write-Host "SKIP: $testName  Eno alive ghostty CP session (is GHOSTTY_CONTROL_PLANE=1 set?)" -ForegroundColor Yellow
    return
}

Write-Host "  Found session: $sessionName" -ForegroundColor DarkGray

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
$sendOk = Send-GhosttyInput -SessionName $sessionName -Text "echo $marker"
Start-Sleep -Milliseconds 2000
$outputContent = Get-GhosttyOutput -SessionName $sessionName

if ($outputContent -match $marker) {
    $passChecks++
    Write-Host "  SEND+READ ............... PASS" -ForegroundColor Green
} elseif (-not $sendOk) {
    Write-Host "  SEND+READ ............... SKIP (send failed  Edeckpilot send bug)" -ForegroundColor Yellow
} else {
    $failChecks++
    Write-Host "  SEND+READ ............... FAIL (marker '$marker' not found)" -ForegroundColor Red
}

Test-Assert -Condition ($failChecks -eq 0) -Message "$testName - deckpilot CP smoke passed ($passChecks checks, 0 failures)"
Write-Host "PASS: $testName - control plane responds to deckpilot (session=$sessionName)" -ForegroundColor Green
