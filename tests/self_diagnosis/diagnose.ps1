#Requires -Version 5.1
<#
.SYNOPSIS
    ghostty-win self-diagnosis script.
    Validates build artifacts, CP protocol, input delivery, concurrency, and stability.

.DESCRIPTION
    Two modes:
      -Attach   : Test the ALREADY RUNNING ghostty (safe from inside ghostty)
      (default) : Launch a new ghostty, test it, then kill it

    Tests:
      1. Build artifact existence (zig-out-winui3/bin/ghostty.exe)
      2. CP session discovery / file verification
      3. CP PING response
      4. CP TAIL/STATE normal response
      5. INPUT/RAW_INPUT key delivery (echo command via CP, verify in TAIL)
      6. Parallel PING (10 concurrent)
      7. Process memory/CPU sanity check
      8. Endurance: continuous PING+TAIL without crash

.NOTES
    Requires: GHOSTTY_CONTROL_PLANE=1 environment variable.
    No mouse input is used (CLAUDE.md compliance).
#>

param(
    [switch]$Attach,
    [switch]$SkipEndurance,
    [int]$EnduranceSeconds = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ============================================================
# Globals
# ============================================================
$script:RepoRoot    = (Resolve-Path "$PSScriptRoot\..\..").Path
$script:GhosttyExe = Join-Path $RepoRoot "zig-out-winui3\bin\ghostty.exe"
$script:SessionDir  = Join-Path $env:LOCALAPPDATA "ghostty\control-plane\winui3\sessions"
$script:Results     = [ordered]@{}
$script:GhosttyProc = $null
$script:PipeName    = $null
$script:Launched    = $false  # true if we launched ghostty (need to kill on cleanup)

# ============================================================
# Helpers
# ============================================================
function Report([string]$Name, [bool]$Pass, [string]$Detail = "") {
    $script:Results[$Name] = @{ Pass = $Pass; Detail = $Detail }
    $color = if ($Pass) { "Green" } else { "Red" }
    $status = if ($Pass) { "PASS" } else { "FAIL" }
    $msg = "${status}: $Name"
    if ($Detail) { $msg += " -- $Detail" }
    Write-Host $msg -ForegroundColor $color
}

function Send-CpCommand([string]$PipeName, [string]$Command, [int]$TimeoutMs = 5000) {
    try {
        $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(
            ".", $PipeName, [System.IO.Pipes.PipeDirection]::InOut,
            [System.IO.Pipes.PipeOptions]::None)
        $pipe.Connect($TimeoutMs)

        $writer = New-Object System.IO.StreamWriter($pipe)
        $writer.AutoFlush = $true
        $writer.WriteLine($Command)

        # Signal end of write
        $pipe.WaitForPipeDrain()

        $reader = New-Object System.IO.StreamReader($pipe)
        $response = $reader.ReadToEnd()

        $reader.Close()
        $writer.Close()
        $pipe.Close()

        return $response.Trim()
    } catch {
        return "ERROR: $($_.Exception.Message)"
    }
}

function Find-SessionFile([int]$Pid) {
    if (-not (Test-Path $script:SessionDir)) { return $null }
    $files = Get-ChildItem $script:SessionDir -Filter "*.session" |
             Where-Object { $_.Name -match "-${Pid}\.session$" }
    if ($files) { return $files[0].FullName }
    return $null
}

function Find-AnyAliveSession() {
    if (-not (Test-Path $script:SessionDir)) { return $null }
    $files = Get-ChildItem $script:SessionDir -Filter "*.session"
    foreach ($f in $files) {
        $props = Parse-SessionFile $f.FullName
        if ($props.ContainsKey("pid")) {
            $pid = [int]$props["pid"]
            try {
                $proc = Get-Process -Id $pid -ErrorAction Stop
                return @{ Path = $f.FullName; PID = $pid; Process = $proc }
            } catch {}
        }
    }
    return $null
}

function Parse-SessionFile([string]$Path) {
    $props = @{}
    Get-Content $Path | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            $props[$Matches[1]] = $Matches[2]
        }
    }
    return $props
}

function Get-PipeNameFromSession([string]$SessionPath) {
    $props = Parse-SessionFile $SessionPath
    if ($props.ContainsKey("pipe_path")) {
        $full = $props["pipe_path"]
        if ($full -match '\\\\\.\\pipe\\(.+)$') {
            return $Matches[1]
        }
    }
    return $null
}

# ============================================================
# Test 1: Build artifact existence
# ============================================================
Write-Host "`n=== Test 1: Build Artifact ===" -ForegroundColor Cyan

$exeExists = Test-Path $script:GhosttyExe
Report "build-artifact" $exeExists $(if ($exeExists) { $script:GhosttyExe } else { "Not found: $($script:GhosttyExe)" })

if (-not $exeExists) {
    Write-Host "`nCannot continue without ghostty.exe. Run ./build-winui3.sh first." -ForegroundColor Red
    exit 1
}

$priFile = Join-Path $RepoRoot "zig-out-winui3\bin\resources.pri"
$priExists = Test-Path $priFile
Report "resources-pri" $priExists $(if ($priExists) { "resources.pri found" } else { "Missing resources.pri" })

# ============================================================
# Test 2: Session discovery (Attach or Launch)
# ============================================================
Write-Host "`n=== Test 2: Session Discovery ===" -ForegroundColor Cyan

$sessionPath = $null
$ghosttyPid = 0

if ($Attach) {
    # ---- Attach mode: find an already-running ghostty ----
    Write-Host "  Mode: Attach (testing current ghostty)" -ForegroundColor DarkGray
    $alive = Find-AnyAliveSession
    if ($alive) {
        $sessionPath = $alive.Path
        $ghosttyPid = $alive.PID
        $script:GhosttyProc = $alive.Process
        Write-Host "  Found alive session PID=$ghosttyPid" -ForegroundColor DarkGray
    }
    Report "session-discovery" ($null -ne $alive) $(if ($alive) { "Attached to PID=$ghosttyPid" } else { "No alive ghostty session found. Launch ghostty with GHOSTTY_CONTROL_PLANE=1 first." })
    if (-not $alive) { exit 1 }
} else {
    # ---- Launch mode: start a new ghostty ----
    Write-Host "  Mode: Launch (starting new ghostty)" -ForegroundColor DarkGray

    $env:GHOSTTY_CONTROL_PLANE = "1"
    $env:GHOSTTY_SESSION_NAME = "diag-test"

    try {
        $script:GhosttyProc = Start-Process -FilePath $script:GhosttyExe -PassThru -WindowStyle Normal
        $ghosttyPid = $script:GhosttyProc.Id
        $script:Launched = $true
        Write-Host "  Launched ghostty PID=$ghosttyPid" -ForegroundColor DarkGray
    } catch {
        Report "launch" $false "Failed to start: $($_.Exception.Message)"
        exit 1
    }

    # Wait for session file (up to 15s)
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        $sessionPath = Find-SessionFile $ghosttyPid
        if ($sessionPath) { break }
        Start-Sleep -Milliseconds 500
    }

    $sessionOk = $null -ne $sessionPath
    Report "session-file" $sessionOk $(if ($sessionOk) { Split-Path $sessionPath -Leaf } else { "No .session file after 15s" })

    if (-not $sessionOk) {
        Write-Host "  Cannot continue without CP session. Is GHOSTTY_CONTROL_PLANE=1 working?" -ForegroundColor Red
        if ($script:GhosttyProc -and -not $script:GhosttyProc.HasExited) {
            Stop-Process -Id $script:GhosttyProc.Id -Force -ErrorAction SilentlyContinue
        }
        exit 1
    }
}

# Extract pipe name
$script:PipeName = Get-PipeNameFromSession $sessionPath
if (-not $script:PipeName) {
    Report "pipe-name" $false "Could not parse pipe_path from session file"
    if ($script:Launched) {
        Stop-Process -Id $ghosttyPid -Force -ErrorAction SilentlyContinue
    }
    exit 1
}
Write-Host "  Pipe: \\.\pipe\$($script:PipeName)" -ForegroundColor DarkGray

# Give the pipe server a moment (only needed for fresh launch)
if ($script:Launched) {
    Start-Sleep -Seconds 2
}

# ============================================================
# Test 3: CP PING
# ============================================================
Write-Host "`n=== Test 3: CP PING ===" -ForegroundColor Cyan

$pingResp = Send-CpCommand $script:PipeName "PING"
$pingOk = $pingResp -match "^PONG\|"
Report "cp-ping" $pingOk $pingResp

# ============================================================
# Test 4: CP STATE and TAIL
# ============================================================
Write-Host "`n=== Test 4: CP STATE & TAIL ===" -ForegroundColor Cyan

$stateResp = Send-CpCommand $script:PipeName "STATE"
$stateOk = $stateResp -match "^STATE\|"
Report "cp-state" $stateOk $(if ($stateResp.Length -gt 120) { $stateResp.Substring(0,120) + "..." } else { $stateResp })

$tailResp = Send-CpCommand $script:PipeName "TAIL|5"
$tailOk = $tailResp -match "^TAIL\|"
Report "cp-tail" $tailOk $(if ($tailResp.Length -gt 120) { $tailResp.Substring(0,120) + "..." } else { $tailResp })

$listResp = Send-CpCommand $script:PipeName "LIST_TABS"
$listOk = $listResp -match "^LIST_TABS\|"
Report "cp-list-tabs" $listOk $(if ($listResp.Length -gt 120) { $listResp.Substring(0,120) + "..." } else { $listResp })

# ============================================================
# Test 5: INPUT delivery (send echo command, verify in TAIL)
# ============================================================
Write-Host "`n=== Test 5: INPUT Key Delivery ===" -ForegroundColor Cyan

$marker = "DIAG_MARKER_$(Get-Random -Maximum 99999)"
$inputText = "echo $marker"
$inputB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($inputText))
$enterB64 = [Convert]::ToBase64String([byte[]]@(0x0D))  # \r

# Send text — Zig-native CP returns ACK|, not QUEUED|
$inputResp = Send-CpCommand $script:PipeName "INPUT|diag|$inputB64"
$inputAck = $inputResp -match "^ACK\|"
Report "cp-input-ack" $inputAck $inputResp

# Send Enter via RAW_INPUT
$rawResp = Send-CpCommand $script:PipeName "RAW_INPUT|diag|$enterB64"
$rawAck = $rawResp -match "^ACK\|"
Report "cp-raw-input-ack" $rawAck $rawResp

# Wait for shell to process, then check TAIL for marker
Start-Sleep -Seconds 3

$tailCheck = Send-CpCommand $script:PipeName "TAIL|30"
$markerFound = $tailCheck -match [regex]::Escape($marker)
Report "input-delivery" $markerFound $(if ($markerFound) { "Marker '$marker' found in TAIL" } else { "Marker not found in last 30 lines of TAIL" })

# ============================================================
# Test 6: Parallel PING (10 concurrent)
# ============================================================
Write-Host "`n=== Test 6: Parallel PING x10 ===" -ForegroundColor Cyan

$jobs = @()
for ($i = 0; $i -lt 10; $i++) {
    $jobs += Start-Job -ScriptBlock {
        param($pipeName)
        try {
            $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(
                ".", $pipeName, [System.IO.Pipes.PipeDirection]::InOut,
                [System.IO.Pipes.PipeOptions]::None)
            $pipe.Connect(5000)
            $writer = New-Object System.IO.StreamWriter($pipe)
            $writer.AutoFlush = $true
            $writer.WriteLine("PING")
            $pipe.WaitForPipeDrain()
            $reader = New-Object System.IO.StreamReader($pipe)
            $resp = $reader.ReadToEnd().Trim()
            $reader.Close(); $writer.Close(); $pipe.Close()
            return $resp
        } catch {
            return "ERROR: $($_.Exception.Message)"
        }
    } -ArgumentList $script:PipeName
}

$jobResults = $jobs | Wait-Job -Timeout 15 | Receive-Job
$jobs | Remove-Job -Force -ErrorAction SilentlyContinue

$parallelPass = @($jobResults | Where-Object { $_ -match "^PONG\|" }).Count
$parallelTotal = 10
Report "parallel-ping" ($parallelPass -eq $parallelTotal) "$parallelPass/$parallelTotal PONG responses"

# ============================================================
# Test 7: Process Memory & CPU
# ============================================================
Write-Host "`n=== Test 7: Memory & CPU ===" -ForegroundColor Cyan

try {
    $proc = Get-Process -Id $ghosttyPid -ErrorAction Stop
    $memMB = [Math]::Round($proc.WorkingSet64 / 1MB, 1)
    $cpuSec = [Math]::Round($proc.TotalProcessorTime.TotalSeconds, 2)
    $threads = $proc.Threads.Count
    $handles = $proc.HandleCount

    $memOk = $memMB -lt 1024  # < 1GB
    $handleOk = $handles -lt 5000

    Report "memory" $memOk "Working set: ${memMB} MB"
    Report "handles" $handleOk "Handles: $handles, Threads: $threads"
    Report "cpu-usage" $true "CPU time: ${cpuSec}s since launch"
} catch {
    Report "process-stats" $false "Could not read process stats: $($_.Exception.Message)"
}

# ============================================================
# Test 8: Endurance (continuous PING + TAIL)
# ============================================================
if ($SkipEndurance) {
    Write-Host "`n=== Test 8: Endurance (SKIPPED) ===" -ForegroundColor Yellow
    Report "endurance" $true "Skipped via -SkipEndurance"
} else {
    Write-Host "`n=== Test 8: Endurance ($EnduranceSeconds sec) ===" -ForegroundColor Cyan
    Write-Host "  Running PING+TAIL every 1s for $EnduranceSeconds seconds..." -ForegroundColor DarkGray

    $endStart = Get-Date
    $endDeadline = $endStart.AddSeconds($EnduranceSeconds)
    $pingCount = 0
    $pingFail = 0
    $tailCount = 0
    $tailFail = 0
    $crashed = $false
    $peakMemMB = 0
    $lastReport = Get-Date

    while ((Get-Date) -lt $endDeadline) {
        # Check process alive
        if ($script:GhosttyProc.HasExited) {
            $crashed = $true
            break
        }

        # PING
        $pr = Send-CpCommand $script:PipeName "PING" 3000
        $pingCount++
        if ($pr -notmatch "^PONG\|") { $pingFail++ }

        # TAIL
        $tr = Send-CpCommand $script:PipeName "TAIL|1" 3000
        $tailCount++
        if ($tr -notmatch "^TAIL\|") { $tailFail++ }

        # Memory snapshot every 10s
        $now = Get-Date
        if (($now - $lastReport).TotalSeconds -ge 10) {
            try {
                $p = Get-Process -Id $ghosttyPid -ErrorAction Stop
                $curMB = [Math]::Round($p.WorkingSet64 / 1MB, 1)
                if ($curMB -gt $peakMemMB) { $peakMemMB = $curMB }
                $elapsed = [Math]::Round(($now - $endStart).TotalSeconds)
                Write-Host "  [$elapsed s] PING $pingCount (fail $pingFail) | TAIL $tailCount (fail $tailFail) | Mem ${curMB}MB" -ForegroundColor DarkGray
            } catch {}
            $lastReport = $now
        }

        Start-Sleep -Seconds 1
    }

    $duration = [Math]::Round(((Get-Date) - $endStart).TotalSeconds)

    if ($crashed) {
        Report "endurance-alive" $false "ghostty crashed after ${duration}s (exit code: $($script:GhosttyProc.ExitCode))"
    } else {
        Report "endurance-alive" $true "Survived ${duration}s"
    }
    Report "endurance-ping" ($pingFail -eq 0) "PING: $pingCount sent, $pingFail failed"
    Report "endurance-tail" ($tailFail -eq 0) "TAIL: $tailCount sent, $tailFail failed"
    Report "endurance-memory" ($peakMemMB -lt 1024) "Peak memory: ${peakMemMB} MB"
}

# ============================================================
# Cleanup
# ============================================================
Write-Host "`n=== Cleanup ===" -ForegroundColor Cyan

if ($script:Launched -and $script:GhosttyProc -and -not $script:GhosttyProc.HasExited) {
    Stop-Process -Id $script:GhosttyProc.Id -Force -ErrorAction SilentlyContinue
    Write-Host "  Stopped ghostty PID=$($script:GhosttyProc.Id)" -ForegroundColor DarkGray
} elseif (-not $script:Launched) {
    Write-Host "  Attach mode: ghostty left running" -ForegroundColor DarkGray
}

# Clean session file only if we launched
if ($script:Launched -and $sessionPath -and (Test-Path $sessionPath)) {
    Remove-Item $sessionPath -Force -ErrorAction SilentlyContinue
}

# ============================================================
# Summary
# ============================================================
Write-Host "`n" -NoNewline
Write-Host ("=" * 60) -ForegroundColor White
Write-Host "  DIAGNOSIS SUMMARY" -ForegroundColor White
Write-Host ("=" * 60) -ForegroundColor White

$passCount = @($script:Results.Values | Where-Object { $_.Pass }).Count
$failCount = @($script:Results.Values | Where-Object { -not $_.Pass }).Count
$total = $script:Results.Count

foreach ($kv in $script:Results.GetEnumerator()) {
    $icon = if ($kv.Value.Pass) { "[PASS]" } else { "[FAIL]" }
    $color = if ($kv.Value.Pass) { "Green" } else { "Red" }
    $line = "  $icon $($kv.Key)"
    if ($kv.Value.Detail) { $line += " -- $($kv.Value.Detail)" }
    Write-Host $line -ForegroundColor $color
}

Write-Host ""
$summaryColor = if ($failCount -eq 0) { "Green" } else { "Red" }
Write-Host "  Result: $passCount PASS / $failCount FAIL (total $total)" -ForegroundColor $summaryColor
Write-Host ("=" * 60) -ForegroundColor White

exit $failCount
