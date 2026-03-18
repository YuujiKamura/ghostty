param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# test-02e-agent-roundtrip — Launch claude -p via control plane, verify output.
# End-to-end: send command → wait for completion → read buffer → check output.
# Requires: GHOSTTY_CONTROL_PLANE=1 and agent-ctl built.

$ErrorActionPreference = 'Stop'
$testName = "test-02e-agent-roundtrip"

# Find agent-ctl binary
$agentCtl = $null
foreach ($candidate in @(
    "$env:USERPROFILE\agent-relay\target\release\agent-ctl.exe",
    "$env:USERPROFILE\agent-relay\target\debug\agent-ctl.exe"
)) {
    if (Test-Path $candidate) { $agentCtl = $candidate; break }
}

if (-not $agentCtl) {
    Write-Host "SKIP: $testName - agent-ctl.exe not found" -ForegroundColor Yellow
    return
}

# Find alive ghostty session
$listOutput = & $agentCtl list --alive-only 2>&1 | Where-Object { $_ -match "ALIVE.*ghostty" }
if (-not $listOutput -or @($listOutput).Count -eq 0) {
    Write-Host "SKIP: $testName - no alive ghostty session" -ForegroundColor Yellow
    return
}

$sessionLine = if ($listOutput -is [array]) { $listOutput[0] } else { $listOutput }
if ($sessionLine -match 'session=([^\s|]+)') {
    $sessionName = $Matches[1]
} else {
    Write-Host "FAIL: $testName - could not parse session name" -ForegroundColor Red
    throw "FAIL: $testName"
}

Write-Host "  Session: $sessionName" -ForegroundColor DarkGray

# Step 1: Send claude -p command
# Use Start-Process to pass text with spaces as a single argument
$testPrompt = 'claude -p PINEAPPLE --max-turns 1'
Write-Host "  Sending: $testPrompt" -ForegroundColor DarkGray
Start-Process -FilePath $agentCtl -ArgumentList "send","$sessionName","`"$testPrompt`"" -NoNewWindow -Wait 2>&1 | Out-Null
Start-Sleep -Milliseconds 500
Start-Process -FilePath $agentCtl -ArgumentList "raw-send","$sessionName","`r" -NoNewWindow -Wait 2>&1 | Out-Null

# Step 2: Wait for completion (prompt=1, up to 60s)
Write-Host "  Waiting for agent completion (up to 60s)..." -ForegroundColor DarkGray
$completed = $false
$deadline = [DateTime]::UtcNow.AddSeconds(60)

# First wait: expect prompt=0 (agent running) within 10s
$sawRunning = $false
$runDeadline = [DateTime]::UtcNow.AddSeconds(10)
while ([DateTime]::UtcNow -lt $runDeadline) {
    Start-Sleep -Milliseconds 2000
    $stateOut = & $agentCtl state $sessionName 2>&1 | Out-String
    if ($stateOut -match "prompt=0") {
        $sawRunning = $true
        Write-Host "  Agent is running (prompt=0)" -ForegroundColor DarkGray
        break
    }
}

if (-not $sawRunning) {
    # Agent may have already finished (fast response)
    Write-Host "  WARN: Never saw prompt=0 (agent may have finished instantly)" -ForegroundColor Yellow
}

# Then wait for prompt=1 (completion)
while ([DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 3000
    $stateOut = & $agentCtl state $sessionName 2>&1 | Out-String
    if ($stateOut -match "prompt=1") {
        $completed = $true
        Write-Host "  Agent completed (prompt=1)" -ForegroundColor DarkGray
        break
    }
}

Test-Assert -Condition $completed -Message "$testName - agent completed within timeout"

# Step 3: Read buffer and check for expected output
Start-Sleep -Milliseconds 1000
$buffer = & $agentCtl read $sessionName 2>&1 | Out-String

$hasPineapple = $buffer -match "PINEAPPLE"
Write-Host "  Buffer contains PINEAPPLE: $hasPineapple" -ForegroundColor DarkGray

if ($hasPineapple) {
    Write-Host "  PASS: Agent output verified" -ForegroundColor Green
} else {
    Write-Host "  Buffer tail:" -ForegroundColor DarkGray
    $buffer.Split("`n") | Select-Object -Last 10 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
}

Test-Assert -Condition $hasPineapple -Message "$testName - claude -p output contains expected word"

Write-Host "PASS: $testName - agent roundtrip (send → execute → read → verify) succeeded" -ForegroundColor Green
