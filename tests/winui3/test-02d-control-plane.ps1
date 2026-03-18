param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# test-02d-control-plane — Verify control plane DLL responds to agent-ctl smoke test.
# Requires: GHOSTTY_CONTROL_PLANE=1 env var on the shared ghostty process,
# and agent-ctl built at ~/agent-ctl/target/release/ or target/debug/.

$ErrorActionPreference = 'Stop'
$testName = "test-02d-control-plane"

# Find agent-ctl binary
$agentCtl = $null
foreach ($candidate in @(
    "$env:USERPROFILE\agent-relay\target\release\agent-ctl.exe",
    "$env:USERPROFILE\agent-relay\target\debug\agent-ctl.exe"
)) {
    if (Test-Path $candidate) { $agentCtl = $candidate; break }
}

if (-not $agentCtl) {
    Write-Host "SKIP: $testName — agent-ctl.exe not found" -ForegroundColor Yellow
    return
}

# Find alive ghostty session
$listOutput = & $agentCtl list --alive-only 2>&1 | Where-Object { $_ -match "ALIVE.*ghostty" }
if (-not $listOutput -or @($listOutput).Count -eq 0) {
    Write-Host "SKIP: $testName — no alive ghostty session (is GHOSTTY_CONTROL_PLANE=1 set?)" -ForegroundColor Yellow
    return
}

# Extract session name from first alive line
$sessionLine = if ($listOutput -is [array]) { $listOutput[0] } else { $listOutput }
if ($sessionLine -match 'session=([^\s|]+)') {
    $sessionName = $Matches[1]
} else {
    Write-Host "FAIL: $testName — could not parse session name from: $sessionLine" -ForegroundColor Red
    throw "FAIL: $testName"
}

Write-Host "  Found session: $sessionName" -ForegroundColor DarkGray

# Run smoke test
$smokeOutput = & $agentCtl smoke $sessionName 2>&1
$smokeExit = $LASTEXITCODE

# Parse results
# Filter only lines that start with test step names (PING, LIST_TABS, STATE, etc.)
$passCount = @($smokeOutput | Select-String "^\s*(PING|LIST_TABS|STATE|SEND|TAIL).*PASS").Count
$failCount = @($smokeOutput | Select-String "^\s*(PING|LIST_TABS|STATE|SEND|TAIL).*FAIL").Count
# Also check the summary line
$summaryFail = @($smokeOutput | Select-String "^Results:.*\d+ failed").Count
if ($summaryFail -gt 0 -and @($smokeOutput | Select-String "^Results: \d+ passed, 0 failed").Count -eq 0) {
    $failCount = [Math]::Max($failCount, 1)
}

foreach ($line in $smokeOutput) {
    if ($line -match "PASS") {
        Write-Host "  $line" -ForegroundColor Green
    } elseif ($line -match "FAIL") {
        Write-Host "  $line" -ForegroundColor Red
    }
}

Test-Assert -Condition ($failCount -eq 0) -Message "$testName - agent-ctl smoke passed ($passCount checks, 0 failures)"
Write-Host "PASS: $testName - control plane responds to agent-ctl (session=$sessionName)" -ForegroundColor Green
