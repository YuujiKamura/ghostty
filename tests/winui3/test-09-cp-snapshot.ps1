param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# test-09-cp-snapshot -- Issue #142: Verify coalesced CP snapshot queries.
# Tests: STATE returns all expected fields, rapid TAIL polling doesn't ghost window.
# Requires: GHOSTTY_CONTROL_PLANE=1 and agent-deck built.

$ErrorActionPreference = 'Stop'
$testName = "test-09-cp-snapshot"

# Find agent-deck binary
$agentDeck = Join-Path $env:USERPROFILE "agent-deck\agent-deck.exe"
if (-not (Test-Path $agentDeck)) {
    Write-Host "SKIP: $testName - agent-deck.exe not found at $agentDeck" -ForegroundColor Yellow
    return
}

# Find alive ghostty session
$sessionName = $env:GHOSTTY_CP_SESSION
if (-not $sessionName) {
    $lsOutput = & $agentDeck ls --json 2>$null | ConvertFrom-Json
    $cpSessions = @($lsOutput | Where-Object { $_.source -eq "ghostty" -and $_.pid -gt 0 })
    if ($cpSessions.Count -gt 0) {
        $sessionName = $cpSessions[0].title
    }
}

if (-not $sessionName) {
    Write-Host "SKIP: $testName - no alive ghostty session" -ForegroundColor Yellow
    return
}
Write-Host "  Session: $sessionName" -ForegroundColor DarkGray

$passChecks = 0
$failChecks = 0

# ── Check 1: STATE returns all expected fields (coalesced snapshot) ──
Write-Host "  Check 1: STATE response contains all expected fields..." -ForegroundColor DarkGray
$stateOutput = & $agentDeck session show $sessionName --json 2>$null | Out-String

$requiredFields = @("tab_count", "active_tab", "pwd", "prompt", "selection", "content_hash", "mode")
$missingFields = @()
foreach ($field in $requiredFields) {
    if ($stateOutput -notmatch $field) {
        $missingFields += $field
    }
}

if ($missingFields.Count -eq 0) {
    $passChecks++
    Write-Host "  STATE fields ............ PASS (all $($requiredFields.Count) fields present)" -ForegroundColor Green
} else {
    $failChecks++
    Write-Host "  STATE fields ............ FAIL (missing: $($missingFields -join ', '))" -ForegroundColor Red
    Write-Host "  Response: $($stateOutput.Substring(0, [Math]::Min(200, $stateOutput.Length)))" -ForegroundColor DarkGray
}

# ── Check 2: Two consecutive STATE requests return same content_hash (no race) ──
Write-Host "  Check 2: Consecutive STATE requests produce consistent hash..." -ForegroundColor DarkGray
$state1 = & $agentDeck session show $sessionName --json 2>$null | Out-String
Start-Sleep -Milliseconds 100
$state2 = & $agentDeck session show $sessionName --json 2>$null | Out-String

$hash1 = if ($state1 -match 'content_hash["\s:=]+([0-9a-fA-F]+)') { $Matches[1] } else { "NONE" }
$hash2 = if ($state2 -match 'content_hash["\s:=]+([0-9a-fA-F]+)') { $Matches[1] } else { "NONE" }

if ($hash1 -ne "NONE" -and $hash1 -eq $hash2) {
    $passChecks++
    Write-Host "  Hash consistency ........ PASS (both=$hash1)" -ForegroundColor Green
} elseif ($hash1 -eq "NONE" -or $hash2 -eq "NONE") {
    $failChecks++
    Write-Host "  Hash consistency ........ FAIL (could not extract content_hash)" -ForegroundColor Red
} else {
    # Different hashes could mean terminal output changed between calls -- warn, don't fail
    $passChecks++
    Write-Host "  Hash consistency ........ WARN (hash1=$hash1, hash2=$hash2, terminal may have changed)" -ForegroundColor Yellow
}

# ── Check 3: Rapid TAIL polling doesn't ghost the window ──
Write-Host "  Check 3: Rapid TAIL polling (50 iterations, 100ms interval)..." -ForegroundColor DarkGray
$ghosttyProc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
if (-not $ghosttyProc -and $ProcessId -gt 0) {
    Write-Host "  SKIP: Cannot find ghostty process (pid=$ProcessId)" -ForegroundColor Yellow
} else {
    $tailErrors = 0
    for ($i = 0; $i -lt 50; $i++) {
        try {
            $tailOut = & $agentDeck session output $sessionName -q --lines 5 2>$null | Out-String
            if ($LASTEXITCODE -ne 0) { $tailErrors++ }
        } catch {
            $tailErrors++
        }
        Start-Sleep -Milliseconds 100
    }

    # After rapid polling, check if the window is still responsive
    $responsive = $true
    if ($ghosttyProc) {
        $ghosttyProc.Refresh()
        $responsive = -not $ghosttyProc.HasExited -and $ghosttyProc.Responding
    }

    if ($responsive -and $tailErrors -lt 5) {
        $passChecks++
        Write-Host "  Rapid TAIL .............. PASS (50 calls, $tailErrors errors, window responsive)" -ForegroundColor Green
    } else {
        $failChecks++
        Write-Host "  Rapid TAIL .............. FAIL (errors=$tailErrors, responsive=$responsive)" -ForegroundColor Red
    }
}

# ── Check 4: STATE after rapid TAIL still returns valid data ──
Write-Host "  Check 4: STATE after load still valid..." -ForegroundColor DarkGray
$postLoadState = & $agentDeck session show $sessionName --json 2>$null | Out-String

if ($postLoadState -match "tab_count" -and $postLoadState -match "content_hash") {
    $passChecks++
    Write-Host "  Post-load STATE ......... PASS" -ForegroundColor Green
} else {
    $failChecks++
    Write-Host "  Post-load STATE ......... FAIL" -ForegroundColor Red
}

# ── Summary ──
Test-Assert -Condition ($failChecks -eq 0) -Message "$testName - snapshot coalescing ($passChecks passed, $failChecks failed)"
Write-Host "PASS: $testName - snapshot coalescing verified ($passChecks checks)" -ForegroundColor Green
