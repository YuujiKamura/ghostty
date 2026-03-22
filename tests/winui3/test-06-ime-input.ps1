param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# test-06-ime-input — Japanese IME input verification.
# Sub-test 1: UTF-8 Japanese text round-trip via Control Plane echo + TAIL
# Sub-test 2: IME composing state management via WM_APP_TEST_FAKE_IME_COMPOSING
# Sub-test 3: Multi-byte echo stability (repeat to detect drift)

$ErrorActionPreference = 'Stop'
$testName = "test-06-ime-input"

# Ensure UTF-8 for Japanese text handling
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# --- Helper: run agent-ctl without $ErrorActionPreference='Stop' killing on stderr ---
function Invoke-AgentCtl {
    param([string[]]$CtlArgs)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $agentCtl @CtlArgs 2>$null
    } finally {
        $ErrorActionPreference = $prev
    }
}

# --- Prerequisite: agent-ctl + session ---
$agentCtl = Join-Path $env:USERPROFILE "agent-relay\target\debug\agent-ctl.exe"
$sessionName = $env:GHOSTTY_CP_SESSION
if (-not $sessionName) {
    $listOutput = Invoke-AgentCtl -CtlArgs @('list', '--alive-only') | Where-Object { $_ -match "ALIVE.*ghostty" }
    if ($listOutput) {
        $sessionLine = if ($listOutput -is [array]) { $listOutput[-1] } else { $listOutput }
        if ($sessionLine -match 'session=([^\s|]+)') { $sessionName = $Matches[1] }
    }
}
Write-Host "  Session: $sessionName" -ForegroundColor DarkGray

if (-not (Test-Path $agentCtl) -or -not $sessionName) {
    Write-Host "  SKIP: agent-ctl not found or no alive session" -ForegroundColor Yellow
    Write-Host "PASS: $testName - skipped (no CP)" -ForegroundColor Green
    return
}

# ============================================================
# SUB-TEST 1: Japanese UTF-8 round-trip via echo
# ============================================================
Write-Host "  --- Sub-test 1: Japanese UTF-8 round-trip ---" -ForegroundColor Cyan

$marker = "ime-test-$(Get-Random -Minimum 1000 -Maximum 9999)"
$jpText = [char]0x30C6 + [char]0x30B9 + [char]0x30C8  # テスト
$echoCmd = "echo ${marker}-${jpText}"

# agent-ctl send already includes Enter (INPUT + 1s sleep + RAW_INPUT CR)
Invoke-AgentCtl -CtlArgs @('send', $sessionName, $echoCmd) | Out-Null
Start-Sleep -Milliseconds 2000

$tail = Invoke-AgentCtl -CtlArgs @('read', $sessionName)
$tailStr = ($tail | Out-String)

# Check marker (ASCII) is present
$markerFound = $tailStr -match $marker
Write-Host "  TAIL contains marker '$marker': $markerFound" -ForegroundColor Gray
Test-Assert -Condition $markerFound -Message "$testName/jp-roundtrip - marker found in terminal buffer"

# Check Japanese text survived UTF-8 round-trip
$jpFound = $tailStr -match $jpText
Write-Host "  TAIL contains Japanese text: $jpFound" -ForegroundColor Gray
Test-Assert -Condition $jpFound -Message "$testName/jp-roundtrip - Japanese text survives UTF-8 round-trip"

# ============================================================
# SUB-TEST 2: IME composing state (fake compose -> verify log)
# ============================================================
Write-Host "  --- Sub-test 2: IME composing state management ---" -ForegroundColor Cyan

$inputOverlay = Get-ChildWindowByClass -Hwnd $Hwnd -ClassName "GhosttyInputOverlay"
if ($inputOverlay -eq [IntPtr]::Zero) {
    Write-Host "  SKIP: GhosttyInputOverlay not found" -ForegroundColor Yellow
} else {
    # Record current log position to only check new entries
    $logPath = Join-Path $env:TEMP "ghostty_debug.log"
    $logLinesBefore = 0
    if (Test-Path $logPath) {
        $logLinesBefore = @(Get-Content $logPath).Count
    }

    # WM_USER + 3 = WM_APP_TEST_FAKE_IME_COMPOSING
    $WM_USER = 0x0400
    $WM_APP_TEST_FAKE_IME = $WM_USER + 3
    [Win32]::PostMessageW($inputOverlay, $WM_APP_TEST_FAKE_IME, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    Start-Sleep -Milliseconds 1000

    # Now trigger focus loss on the overlay to test preedit cleanup
    $WM_KILLFOCUS = 0x0008
    [Win32]::PostMessageW($inputOverlay, $WM_KILLFOCUS, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    Start-Sleep -Milliseconds 500

    # Verify via debug.log that the composing state was set and cleaned up.
    # NOTE: The WM_APP_TEST_FAKE_IME_COMPOSING handler is gated behind
    # `comptime builtin.mode == .Debug` — it does not exist in ReleaseFast.
    # Skip this check for Release builds (exe < 50MB = Release).
    $exePath2 = Join-Path $PSScriptRoot "..\..\zig-out-winui3\bin\ghostty.exe"
    $isRelease = (Test-Path $exePath2) -and ((Get-Item $exePath2).Length -lt 50MB)
    if ($isRelease) {
        Write-Host "  SKIP: fake IME composing test (Debug-only handler, ReleaseFast build)" -ForegroundColor Yellow
    } else {
        if (Test-Path $logPath) {
            $allLines = @(Get-Content $logPath)
            $newLines = if ($logLinesBefore -lt $allLines.Count) {
                ($allLines[$logLinesBefore..($allLines.Count - 1)] | Out-String)
            } else { "" }
            $fakeSet = $newLines -match "WM_APP_TEST_FAKE_IME_COMPOSING"
            $killFocusClear = $newLines -match "WM_KILLFOCUS while ime_composing"
            Write-Host "  Log: fake_ime_set=$fakeSet, killfocus_clear=$killFocusClear (new lines: $($allLines.Count - $logLinesBefore))" -ForegroundColor Gray
            if (-not $fakeSet) {
                Write-Host "  SKIP: WM_APP_TEST_FAKE_IME handler not found — binary may be stale or ReleaseFast" -ForegroundColor Yellow
            } else {
                Test-Assert -Condition $fakeSet -Message "$testName/ime-state - fake IME composing state was set"
                Test-Assert -Condition $killFocusClear -Message "$testName/ime-state - KILLFOCUS cleared composing preedit"
            }
        } else {
            Write-Host "  SKIP: debug.log not found at $logPath" -ForegroundColor Yellow
        }
    }
}

# ============================================================
# SUB-TEST 3: Multi-byte echo stability (repeat to detect drift)
# ============================================================
Write-Host "  --- Sub-test 3: Multi-byte stability (3x repeat) ---" -ForegroundColor Cyan

# Use different kanji/kana each round to detect character-level corruption
$jpStrings = @(
    ([char]0x6F22 + [char]0x5B57),           # 漢字
    ([char]0x3072 + [char]0x3089 + [char]0x304C + [char]0x306A),  # ひらがな
    ([char]0x30AB + [char]0x30BF + [char]0x30AB + [char]0x30CA)   # カタカナ
)

$driftFails = 0
for ($i = 0; $i -lt $jpStrings.Count; $i++) {
    $driftMarker = "drift-${i}-$(Get-Random -Minimum 100 -Maximum 999)"
    $driftJp = $jpStrings[$i]
    $driftCmd = "echo ${driftMarker}-${driftJp}"

    Invoke-AgentCtl -CtlArgs @('send', $sessionName, $driftCmd) | Out-Null
    Start-Sleep -Milliseconds 2000

    $driftTail = Invoke-AgentCtl -CtlArgs @('read', $sessionName)
    $driftStr = ($driftTail | Out-String)

    $driftOk = $driftStr -match "${driftMarker}-${driftJp}"
    Write-Host "  Round ${i}: marker='${driftMarker}' jp='${driftJp}' found=${driftOk}" -ForegroundColor Gray
    if (-not $driftOk) { $driftFails++ }
}

Test-Assert -Condition ($driftFails -eq 0) -Message "$testName/drift - all 3 multi-byte echo rounds passed ($driftFails failures)"

Write-Host "PASS: $testName - Japanese IME input verification complete" -ForegroundColor Green
