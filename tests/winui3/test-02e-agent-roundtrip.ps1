param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# test-02e-agent-roundtrip — Launch claude -p via control plane, verify output.
# End-to-end: send command → wait for completion → read buffer → check output.
# Requires: GHOSTTY_CONTROL_PLANE=1 and agent-deck built.

$ErrorActionPreference = 'Stop'
$testName = "test-02e-agent-roundtrip"

# Find agent-deck binary
$agentDeck = Join-Path $env:USERPROFILE "agent-deck\agent-deck.exe"
if (-not (Test-Path $agentDeck)) {
    Write-Host "SKIP: $testName - agent-deck.exe not found" -ForegroundColor Yellow
    return
}

# Find alive ghostty session
$sessionName = $env:GHOSTTY_CP_SESSION
if (-not $sessionName) {
    $lsOutput = & $agentDeck ls --json 2>$null | ConvertFrom-Json
    $cpSessions = @($lsOutput | Where-Object { $_.source -eq "ghostty" })
    if ($cpSessions.Count -gt 0) {
        $sessionName = $cpSessions[0].title
    }
}

if (-not $sessionName) {
    Write-Host "SKIP: $testName - no alive ghostty session" -ForegroundColor Yellow
    return
}
Write-Host "  Session: $sessionName" -ForegroundColor DarkGray

# Step 1: Send claude -p command (atomic: text+Enter in single call)
$testPrompt = 'claude -p PINEAPPLE --max-turns 1'
Write-Host "  Sending: $testPrompt" -ForegroundColor DarkGray
& $agentDeck session send $sessionName $testPrompt --no-wait 2>$null | Out-Null

# Step 2: Wait for completion (up to 90s)
# Poll terminal buffer for PINEAPPLE (agent output)
Write-Host "  Waiting for agent completion (up to 90s)..." -ForegroundColor DarkGray
$completed = $false
$deadline = [DateTime]::UtcNow.AddSeconds(90)

while ([DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 3000
    $buffer = & $agentDeck session output $sessionName -q 2>$null | Out-String
    if ($buffer -match "PINEAPPLE") {
        $completed = $true
        Write-Host "  Agent output contains PINEAPPLE" -ForegroundColor DarkGray
        break
    }
}

Test-Assert -Condition $completed -Message "$testName - agent completed within timeout"

# Step 3: Verify output
$buffer = & $agentDeck session output $sessionName -q 2>$null | Out-String
$hasPineapple = $buffer -match "PINEAPPLE"
Write-Host "  Buffer contains PINEAPPLE: $hasPineapple" -ForegroundColor DarkGray

if (-not $hasPineapple) {
    Write-Host "  Buffer tail:" -ForegroundColor DarkGray
    $buffer.Split("`n") | Select-Object -Last 10 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
}

Test-Assert -Condition $hasPineapple -Message "$testName - claude -p output contains expected word"

Write-Host "PASS: $testName - agent roundtrip (send → execute → read → verify) succeeded" -ForegroundColor Green
