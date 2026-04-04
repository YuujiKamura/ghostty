# run-all-tests.ps1 — winui3 integration test runner
# Usage: pwsh.exe -File run-all-tests.ps1
#
# Ghostty 1 (test target): Started via Start-Ghostty, stays alive for all phases
# Test driver: PowerShell process calls deckpilot.exe directly (no Ghostty 2 needed)
#
# Phase 1: Lifecycle — ghost-demo (tab1), noise ghost-demo (tab2), UI checks
# Phase 2: CP roundtrip — deckpilot send/show
# Phase 3: CP input — ASCII + Japanese via deckpilot
# Cleanup: Stop Ghostty 1

param(
    [string]$ExePath,
    [switch]$SkipBuild,
    [switch]$OnlyFailed
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module "$PSScriptRoot\test-helpers.psm1" -Force

# --- Build check ---
if (-not $ExePath) {
    $ExePath = Join-Path $PSScriptRoot "..\..\zig-out-winui3\bin\ghostty.exe"
}

if (-not (Test-Path $ExePath)) {
    Write-Host "ERROR: ghostty.exe not found at $ExePath" -ForegroundColor Red
    Write-Host "Build first: ./build-winui3.sh" -ForegroundColor Yellow
    exit 1
}

$deckpilot = Join-Path $env:USERPROFILE "deckpilot\deckpilot.exe"

$results = @()

# --- OnlyFailed: load previous results and build filter set ---
$failedNames = $null
if ($OnlyFailed) {
    $lastResultsPath = Join-Path $PSScriptRoot ".last-results.json"
    if (-not (Test-Path $lastResultsPath)) {
        Write-Host "No previous failures found. Run full suite first." -ForegroundColor Yellow
        exit 0
    }
    $lastResults = Get-Content $lastResultsPath -Raw | ConvertFrom-Json
    $failedNames = @($lastResults | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object { $_.Name })
    if ($failedNames.Count -eq 0) {
        Write-Host "No previous failures found. Run full suite first." -ForegroundColor Yellow
        exit 0
    }
    Write-Host "`n=== Re-running $($failedNames.Count) previously failed test(s) ===" -ForegroundColor Magenta
    $failedNames | ForEach-Object { Write-Host "  - $_" -ForegroundColor Magenta }
}

# --- Test names ---
$phase1Tests = @(
    "phase1-ghost-demo-smoke",
    "phase1-noise-ghost-demo",
    "test-02b-ime-overlay",
    "test-02c-drag-bar",
    "test-03-window-ops"
)

$phase2Tests = @(
    "phase2-session-detect",
    "phase2-send-show-roundtrip"
)

$phase3Tests = @(
    "phase3-ascii-input",
    "phase3-japanese-input"
)

# --- OnlyFailed: filter ---
if ($failedNames) {
    $phase1Tests = @($phase1Tests | Where-Object { $_ -in $failedNames })
    $phase2Tests = @($phase2Tests | Where-Object { $_ -in $failedNames })
    $phase3Tests = @($phase3Tests | Where-Object { $_ -in $failedNames })
}

$needGhostty = ($phase1Tests.Count -gt 0 -or $phase2Tests.Count -gt 0 -or $phase3Tests.Count -gt 0)
if (-not $needGhostty) {
    Write-Host "  SKIP: No tests to run" -ForegroundColor DarkGray
    @() | ConvertTo-Json -Depth 2 | Set-Content (Join-Path $PSScriptRoot ".last-results.json") -Encoding UTF8
    exit 0
}

# ============================================================
# Helper: run a named test block, record result
# ============================================================
function Invoke-Test {
    param(
        [string]$Name,
        [scriptblock]$Block
    )
    $startTime = [DateTime]::UtcNow
    try {
        & $Block
        $elapsed = ([DateTime]::UtcNow - $startTime).TotalMilliseconds
        $script:results += @{ Name = $Name; Status = "PASS"; Time = [int]$elapsed; Error = $null }
    } catch {
        $elapsed = ([DateTime]::UtcNow - $startTime).TotalMilliseconds
        $script:results += @{ Name = $Name; Status = "FAIL"; Time = [int]$elapsed; Error = $_.Exception.Message }
        Write-Host "`n--- $Name (FAIL) ---" -ForegroundColor Red
        Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ============================================================
# Launch Ghostty 1 (test target)
# ============================================================
Write-Host "`n=== Launching Ghostty 1 (test target) ===" -ForegroundColor Cyan
$env:GHOSTTY_CONTROL_PLANE = "1"

# Clean stale ghostty session files
$ghosttySessionDir = Join-Path $env:LOCALAPPDATA "ghostty\control-plane\winui3\sessions"
foreach ($sessionDir in @($ghosttySessionDir, (Join-Path $env:LOCALAPPDATA "WindowsTerminal\control-plane\winui3\sessions"))) {
    if (Test-Path $sessionDir) {
        Get-ChildItem "$sessionDir\ghostty-*.session" -ErrorAction SilentlyContinue | ForEach-Object {
            $content = Get-Content $_.FullName -Raw
            if ($content -match 'pid=(\d+)') {
                $sessionPid = [int]$Matches[1]
                $liveProc = Get-Process -Id $sessionPid -ErrorAction SilentlyContinue
                $isGhostty = $liveProc -and ($liveProc.ProcessName -eq 'ghostty')
                if (-not $isGhostty) {
                    Remove-Item $_.FullName -Force
                    Write-Host "  Cleaned stale session: $($_.Name)" -ForegroundColor DarkGray
                }
            }
        }
    }
}

$proc = Start-Ghostty -ExePath $ExePath
$hwnd = [IntPtr]::Zero

try {
    $hwnd = Find-GhosttyWindow -ProcessId $proc.Id -TimeoutMs 15000
    Write-Host "  Window ready: HWND=0x$($hwnd.ToString('X'))" -ForegroundColor Green
} catch {
    Write-Host "FATAL: Could not find Ghostty window: $_" -ForegroundColor Red
    Stop-Ghostty -Process $proc
    exit 1
}

# Give XAML time to fully initialize + CP DLL to register session
Start-Sleep -Milliseconds 3000

# Discover the ghostty CP session via deckpilot
$sessionName = ""
$registered = Register-GhosttyCP -ProcessId $proc.Id
if ($registered) {
    $sessionName = $registered
    Write-Host "  CP session: $sessionName" -ForegroundColor Green
} else {
    $discovered = Find-GhosttyCP -ProcessId $proc.Id
    if ($discovered) {
        $sessionName = $discovered
        Write-Host "  CP session (discovered): $sessionName" -ForegroundColor Green
    } else {
        Write-Host "  WARN: Could not identify ghostty CP session" -ForegroundColor Yellow
    }
}
$env:GHOSTTY_CP_SESSION = $sessionName

# ============================================================
# Phase 1: Lifecycle
# ============================================================
Write-Host "`n=== Phase 1: Lifecycle ===" -ForegroundColor Cyan

$playPy = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "tools\ghost-demo\play.py"

# --- Phase 1: ghost-demo smoke (tab 1) ---
if ("phase1-ghost-demo-smoke" -in $phase1Tests) {
    Invoke-Test -Name "phase1-ghost-demo-smoke" -Block {
        # Verify process alive
        $proc.Refresh()
        Test-Assert -Condition (-not $proc.HasExited) -Message "phase1-ghost-demo-smoke - process alive"

        # Read log to verify init
        $logPath = Join-Path $env:TEMP "ghostty_debug.log"
        $logContent = ""
        if (Test-Path $logPath) {
            try {
                $fs = [System.IO.FileStream]::new($logPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
                $reader = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
                $logContent = $reader.ReadToEnd()
                $reader.Dispose()
                $fs.Dispose()
            } catch {
                Write-Host "  WARN: Could not read log: $_" -ForegroundColor Yellow
            }
        }

        Test-Assert -Condition ($logContent -match "App.init: EXIT OK") -Message "phase1-ghost-demo-smoke - App.init completed"
        Test-Assert -Condition ($logContent -match "initXaml step 8") -Message "phase1-ghost-demo-smoke - initXaml step 8 reached"
        Test-Assert -Condition ($logContent -match "Present OK") -Message "phase1-ghost-demo-smoke - D3D11 rendering active"

        $hasCpOk = ($logContent -match "control plane DLL started") -or ($logContent -match "control plane started")
        Test-Assert -Condition $hasCpOk -Message "phase1-ghost-demo-smoke - Control plane loaded"

        # Run ghost-demo on tab 1 via CP
        if ($sessionName) {
            $sendOk = Send-GhosttyInput -SessionName $sessionName -Text "python `"$playPy`" --fps 60"
            if ($sendOk) {
                Write-Host "  Sent play.py --fps 60 to tab 1" -ForegroundColor DarkGray
            } else {
                Write-Host "  WARN: Could not send play.py" -ForegroundColor Yellow
            }
            Start-Sleep -Seconds 8
            Send-GhosttyInput -SessionName $sessionName -Text "`u{0003}" | Out-Null
            Start-Sleep -Milliseconds 500
        } else {
            Write-Host "  WARN: No CP session, skipping demo playback" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "  SKIP: phase1-ghost-demo-smoke" -ForegroundColor DarkGray
}

# --- Phase 1: noise ghost-demo (same tab, no tab creation via CP) ---
if ("phase1-noise-ghost-demo" -in $phase1Tests) {
    Invoke-Test -Name "phase1-noise-ghost-demo" -Block {
        if (-not $sessionName) {
            throw "No CP session available"
        }

        # NOTE: deckpilot send is INPUT-only (types text into shell).
        # It cannot invoke CP actions like new_tab, so we run the noise
        # demo in the existing session (tab 1) instead of opening tab 2.

        $sendOk = Send-GhosttyInput -SessionName $sessionName -Text "python `"$playPy`" --fps 60"
        if ($sendOk) {
            Write-Host "  Sent noise play.py --fps 60 to $sessionName" -ForegroundColor DarkGray
        } else {
            Write-Host "  WARN: Could not send noise play.py" -ForegroundColor Yellow
        }

        # Let it run briefly, then verify process still alive
        Start-Sleep -Seconds 4
        $proc.Refresh()
        Test-Assert -Condition (-not $proc.HasExited) -Message "phase1-noise-ghost-demo - process alive during demo"

        # Stop noise demo
        Send-GhosttyInput -SessionName $sessionName -Text "`u{0003}" | Out-Null
        Start-Sleep -Milliseconds 500
    }
} else {
    Write-Host "  SKIP: phase1-noise-ghost-demo" -ForegroundColor DarkGray
}

# --- Phase 1: UI tests via individual scripts ---
foreach ($testBaseName in @("test-02b-ime-overlay", "test-02c-drag-bar", "test-03-window-ops")) {
    if ($testBaseName -notin $phase1Tests) {
        Write-Host "  SKIP: $testBaseName" -ForegroundColor DarkGray
        continue
    }

    $testPath = Join-Path $PSScriptRoot "$testBaseName.ps1"
    if (-not (Test-Path $testPath)) {
        Write-Host "`n--- $testBaseName --- SKIP (not found)" -ForegroundColor Yellow
        continue
    }

    Invoke-Test -Name $testBaseName -Block {
        & $testPath -Hwnd $hwnd -ProcessId $proc.Id 6>&1 | Out-Null
    }
}

# ============================================================
# Phase 2: CP roundtrip
# ============================================================
Write-Host "`n=== Phase 2: CP roundtrip ===" -ForegroundColor Cyan

if (-not (Test-Path $deckpilot)) {
    Write-Host "  SKIP: deckpilot.exe not found at $deckpilot" -ForegroundColor Yellow
} else {

    # --- Phase 2: session detect ---
    if ("phase2-session-detect" -in $phase2Tests) {
        Invoke-Test -Name "phase2-session-detect" -Block {
            $json = & $deckpilot list --json 2>$null | ConvertFrom-Json
            $sessions = @($json | Where-Object { $_.pid -eq $proc.Id })
            Test-Assert -Condition ($sessions.Count -ge 1) -Message "phase2-session-detect - deckpilot list finds session for PID $($proc.Id)"
            Write-Host "  Sessions found: $($sessions.Count)" -ForegroundColor DarkGray
            $sessions | ForEach-Object { Write-Host "    - $($_.name)" -ForegroundColor DarkGray }
        }
    } else {
        Write-Host "  SKIP: phase2-session-detect" -ForegroundColor DarkGray
    }

    # --- Phase 2: send/show roundtrip ---
    if ("phase2-send-show-roundtrip" -in $phase2Tests) {
        Invoke-Test -Name "phase2-send-show-roundtrip" -Block {
            if (-not $sessionName) {
                throw "No CP session available"
            }

            $marker = "roundtrip_marker_$(Get-Random)"
            & $deckpilot send $sessionName "echo $marker" 2>$null
            Start-Sleep -Seconds 3

            $buffer = & $deckpilot show $sessionName 2>$null
            $bufferText = $buffer -join "`n"
            Test-Assert -Condition ($bufferText -match $marker) -Message "phase2-send-show-roundtrip - buffer contains marker '$marker'"
        }
    } else {
        Write-Host "  SKIP: phase2-send-show-roundtrip" -ForegroundColor DarkGray
    }
}

# ============================================================
# Phase 3: CP input
# ============================================================
Write-Host "`n=== Phase 3: CP input ===" -ForegroundColor Cyan

if (-not (Test-Path $deckpilot)) {
    Write-Host "  SKIP: deckpilot.exe not found at $deckpilot" -ForegroundColor Yellow
} else {

    # --- Phase 3: ASCII input ---
    if ("phase3-ascii-input" -in $phase3Tests) {
        Invoke-Test -Name "phase3-ascii-input" -Block {
            if (-not $sessionName) {
                throw "No CP session available"
            }

            $marker = "keyboard_test_marker_$(Get-Random)"
            & $deckpilot send $sessionName "echo $marker" 2>$null
            Start-Sleep -Seconds 3

            $buffer = & $deckpilot show $sessionName 2>$null
            $bufferText = $buffer -join "`n"
            Test-Assert -Condition ($bufferText -match $marker) -Message "phase3-ascii-input - ASCII marker found in buffer"
        }
    } else {
        Write-Host "  SKIP: phase3-ascii-input" -ForegroundColor DarkGray
    }

    # --- Phase 3: Japanese input ---
    if ("phase3-japanese-input" -in $phase3Tests) {
        Invoke-Test -Name "phase3-japanese-input" -Block {
            if (-not $sessionName) {
                throw "No CP session available"
            }

            & $deckpilot send $sessionName "echo $([char]0x30C6)$([char]0x30B9)$([char]0x30C8)" 2>$null
            Start-Sleep -Seconds 3

            $buffer = & $deckpilot show $sessionName 2>$null
            $bufferText = $buffer -join "`n"
            Test-Assert -Condition ($bufferText -match "$([char]0x30C6)$([char]0x30B9)$([char]0x30C8)") -Message "phase3-japanese-input - Japanese text found in buffer"
        }
    } else {
        Write-Host "  SKIP: phase3-japanese-input" -ForegroundColor DarkGray
    }
}

# ============================================================
# Cleanup: Stop Ghostty 1
# ============================================================
Write-Host "`n=== Stopping Ghostty ===" -ForegroundColor Cyan
Stop-Ghostty -Process $proc

# --- Summary ---
Write-Host "`n============================================" -ForegroundColor White
Write-Host "  TEST RESULTS" -ForegroundColor White
Write-Host "============================================" -ForegroundColor White

$passed = @($results | Where-Object { $_.Status -eq "PASS" }).Count
$failed = @($results | Where-Object { $_.Status -eq "FAIL" }).Count
$total = $results.Count

foreach ($r in $results) {
    $color = if ($r.Status -eq "PASS") { "Green" } else { "Red" }
    $timeStr = "$($r.Time)ms"
    $line = "  [{0}] {1} ({2})" -f $r.Status, $r.Name, $timeStr
    Write-Host $line -ForegroundColor $color
    if ($r.Error) {
        Write-Host "         $($r.Error)" -ForegroundColor DarkRed
    }
}

Write-Host "--------------------------------------------" -ForegroundColor White
$summaryColor = if ($failed -eq 0) { "Green" } else { "Red" }
Write-Host "  $passed/$total passed, $failed failed" -ForegroundColor $summaryColor
Write-Host "============================================`n" -ForegroundColor White

# --- Save results to .last-results.json for -OnlyFailed re-runs ---
$jsonResults = $results | ForEach-Object {
    [PSCustomObject]@{ Name = $_.Name; Status = $_.Status; Time = $_.Time; Error = $_.Error }
}
$jsonResults | ConvertTo-Json -Depth 2 | Set-Content (Join-Path $PSScriptRoot ".last-results.json") -Encoding UTF8

exit $failed
