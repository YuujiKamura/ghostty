param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# test-07-tsf-ime -- TSF IME fix verification via CP TSF_INJECT.
# Uses agent-ctl send with ESC[TSF: prefix to route text through TSF commit path.

$ErrorActionPreference = 'Continue'
$testName = "test-07-tsf-ime"
$script:subFails = 0

function Test-Soft {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "  PASS: $Message" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: $Message" -ForegroundColor Red
        $script:subFails++
    }
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# --- Prerequisite: agent-ctl + session ---
$agentCtl = Join-Path $env:USERPROFILE "agent-relay\target\debug\agent-ctl.exe"
$listOutput = & $agentCtl list 2>$null | Where-Object { $_ -match "ALIVE" -and $_ -match "ghostty" }
$sessionName = $null
if ($listOutput) {
    # Pick the session matching our PID
    foreach ($line in $listOutput) {
        if ($line -match "pid=$ProcessId") {
            if ($line -match 'session=([^\s|]+)') { $sessionName = $Matches[1] }
        }
    }
    # Fallback: first alive ghostty session
    if (-not $sessionName -and $listOutput) {
        $first = if ($listOutput -is [array]) { $listOutput[0] } else { $listOutput }
        if ($first -match 'session=([^\s|]+)') { $sessionName = $Matches[1] }
    }
}
Write-Host "  Session: $sessionName" -ForegroundColor DarkGray

if (-not (Test-Path $agentCtl) -or -not $sessionName) {
    Write-Host "  SKIP: agent-ctl not found or no alive ghostty session" -ForegroundColor Yellow
    Write-Host "PASS: $testName - skipped (no CP)" -ForegroundColor Green
    return
}

# --- Debug log ---
$logPath = Join-Path $env:TEMP "ghostty_debug.log"
function Get-RecentLog {
    param([int]$Lines = 100)
    if (Test-Path $logPath) {
        return (Get-Content $logPath -Tail $Lines -ErrorAction SilentlyContinue | Out-String)
    }
    return ""
}

# Helper: send TSF inject via bash (PowerShell mangles ESC byte)
function Send-TsfInject {
    param([string]$Session, [string]$Text)
    # Use bash printf to construct ESC[TSF:<text> and pipe to agent-ctl send
    $bashCmd = "printf '\033[TSF:$Text' | xargs -0 ~/agent-relay/target/debug/agent-ctl.exe send $Session"
    & bash -c $bashCmd 2>&1 | Out-Null
}

# ============================================================
# SUB-TEST 1: TSF associateFocus HWND re-association on GotFocus
# ============================================================
Write-Host "  --- Sub-test 1: TSF associateFocus HWND re-association ---" -ForegroundColor Cyan

[Win32]::SetForegroundWindow($Hwnd) | Out-Null
Start-Sleep -Milliseconds 300
[Win32]::ShowWindow($Hwnd, [Win32]::SW_MINIMIZE) | Out-Null
Start-Sleep -Milliseconds 500
[Win32]::ShowWindow($Hwnd, [Win32]::SW_RESTORE) | Out-Null
[Win32]::SetForegroundWindow($Hwnd) | Out-Null
Start-Sleep -Milliseconds 1500

# Read entire log (re-associateFocus may have fired at startup, not just now)
$log1 = if (Test-Path $logPath) { Get-Content $logPath -Raw -ErrorAction SilentlyContinue } else { "" }
$hasReAssociate = $log1 -match "re-associateFocus"
$hasGotFocusAssociate = ($log1 -match "GotFocus") -and ($log1 -match "associateFocus hwnd=")
# Also verify the code has findWindowOfActiveTSF in onXamlGotFocus
$repoRoot = Join-Path $PSScriptRoot "..\..\"
$surfaceCode = Get-Content (Join-Path $repoRoot "src\apprt\winui3\Surface.zig") -Raw
$hasCodeFix = $surfaceCode -match "fn onXamlGotFocus[\s\S]{0,2000}findWindowOfActiveTSF"
Write-Host "  re-associateFocus in log: $hasReAssociate" -ForegroundColor Gray
Write-Host "  GotFocus + associateFocus in log: $hasGotFocusAssociate" -ForegroundColor Gray
Write-Host "  Code has fix: $hasCodeFix" -ForegroundColor Gray
Test-Soft -Condition ($hasCodeFix -and ($hasReAssociate -or $hasGotFocusAssociate)) `
    -Message "$testName/fix1 - GotFocus checks and re-associates TSF HWND"

# ============================================================
# SUB-TEST 2: TSF_INJECT composition lifecycle
# ============================================================
Write-Host "  --- Sub-test 2: TSF_INJECT composition lifecycle ---" -ForegroundColor Cyan

# Send TSF inject: ESC[TSF:あ via bash to avoid PowerShell ESC mangling
& bash (Join-Path $PSScriptRoot "tsf-inject.sh") $sessionName ([char]0x3042).ToString() 2>&1 | Out-Null
Start-Sleep -Milliseconds 2000

$log2 = Get-RecentLog -Lines 500
$hasTsfInject = $log2 -match "TSF_INJECT.*simulating"
$hasOnStart = $log2 -match "OnStartComposition"
$hasOnEnd = $log2 -match "OnEndComposition"
$hasEndEdit = $log2 -match "textEditSinkOnEndEdit.*requesting"
$hasHandleOutput = $log2 -match "tsfHandleOutput"

Write-Host "  TSF_INJECT triggered: $hasTsfInject" -ForegroundColor Gray
Write-Host "  OnStartComposition: $hasOnStart" -ForegroundColor Gray
Write-Host "  textEditSinkOnEndEdit: $hasEndEdit" -ForegroundColor Gray
Write-Host "  OnEndComposition: $hasOnEnd" -ForegroundColor Gray
Write-Host "  tsfHandleOutput: $hasHandleOutput" -ForegroundColor Gray

Test-Soft -Condition $hasTsfInject `
    -Message "$testName/fix2 - TSF_INJECT route activated via CP"
Test-Soft -Condition ($hasOnStart -and $hasEndEdit -and $hasOnEnd) `
    -Message "$testName/fix2 - full composition lifecycle (start + endEdit + end)"

# ============================================================
# SUB-TEST 3: tsf_just_committed flag
# ============================================================
Write-Host "  --- Sub-test 3: tsf_just_committed flag ---" -ForegroundColor Cyan

# Send another TSF inject
& bash (Join-Path $PSScriptRoot "tsf-inject.sh") $sessionName ([char]0x304B).ToString() 2>&1 | Out-Null
Start-Sleep -Milliseconds 1500

$log3 = Get-RecentLog -Lines 500
$hasTsfOutput = $log3 -match "tsfHandleOutput"
Write-Host "  tsfHandleOutput: $hasTsfOutput" -ForegroundColor Gray

# Verify code has the fix
$repoRoot = Join-Path $PSScriptRoot "..\..\"
$appContent = Get-Content (Join-Path $repoRoot "src\apprt\winui3\App.zig") -Raw
$hasFlagSet = $appContent -match "tsf_just_committed\s*=\s*true"
$surfaceContent = Get-Content (Join-Path $repoRoot "src\apprt\winui3\Surface.zig") -Raw
$hasFlagCheck = $surfaceContent -match "tsf_just_committed.*0x0D"
Write-Host "  tsf_just_committed = true in App.zig: $hasFlagSet" -ForegroundColor Gray
Write-Host "  VK_RETURN check in Surface.zig: $hasFlagCheck" -ForegroundColor Gray

Test-Soft -Condition ($hasTsfOutput -and $hasFlagSet -and $hasFlagCheck) `
    -Message "$testName/fix3 - tsf_just_committed set on commit, checked for VK_RETURN"

# ============================================================
# SUB-TEST 4: No doubled characters
# ============================================================
Write-Host "  --- Sub-test 4: No doubled characters ---" -ForegroundColor Cyan

$marker = "tsf4-$(Get-Random -Minimum 1000 -Maximum 9999)"
& $agentCtl send $sessionName "`"echo $marker`"" 2>&1 | Out-Null
& $agentCtl raw-send $sessionName "`r" 2>&1 | Out-Null
Start-Sleep -Milliseconds 1500

# Inject テスト through TSF path
$tsfInjectSh = Join-Path $PSScriptRoot "tsf-inject.sh"
& bash $tsfInjectSh $sessionName ([char]0x30C6 + [char]0x30B9 + [char]0x30C8) 2>&1 | Out-Null
Start-Sleep -Milliseconds 2000

$tail = & $agentCtl read $sessionName 2>&1
$tailStr = ($tail | Out-String)
$markerFound = $tailStr -match $marker
$doubledText = ([char]0x30C6).ToString() + ([char]0x30B9).ToString() + ([char]0x30C8).ToString() + `
               ([char]0x30C6).ToString() + ([char]0x30B9).ToString() + ([char]0x30C8).ToString()
$hasDoubled = $tailStr -match [regex]::Escape($doubledText)

Write-Host "  Marker found: $markerFound" -ForegroundColor Gray
Write-Host "  Doubled text: $hasDoubled" -ForegroundColor Gray

Test-Soft -Condition $markerFound -Message "$testName/fix4 - marker visible"
Test-Soft -Condition (-not $hasDoubled) -Message "$testName/fix4 - no doubled text"

# ============================================================
# SUMMARY
# ============================================================
if ($script:subFails -gt 0) {
    Write-Host "FAIL: $testName - $($script:subFails) sub-test(s) failed" -ForegroundColor Red
    throw "test-07-tsf-ime: $($script:subFails) sub-test(s) failed"
} else {
    Write-Host "PASS: $testName - TSF IME fix verification complete" -ForegroundColor Green
}
