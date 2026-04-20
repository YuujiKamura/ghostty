<#
.SYNOPSIS
    Reproduce issue #214 runtime Dispatcher stall under heavy PTY output burst.
    Measures deckpilot/CP-pipe round-trip latency from a host process while the
    target ghostty session is being flooded with PTY output (simulating a
    Claude xhigh thinking burst).

.DESCRIPTION
    Pre-conditions:
      - Fresh build at zig-out-winui3/bin/ghostty.exe (with TEMP-DIAG counters
        — this is the p1-task-214-dispatcher-stall-mitigation branch).
      - GHOSTTY_WINUI3_DISPATCHER_DIAG=1 is set for the spawned ghostty so the
        diag log is written at %LOCALAPPDATA%\ghostty\dispatcher-stall-diag-<pid>.log.

    Constraint:
      - No more than 3 live ghostty.exe processes during the run (main-thread
        host session plus this spawned session plus at most one other peer).

    Measurement:
      - Latency of a lightweight lock-free CP read (STATE) and a UI-thread
        mutation request (INPUT) at 100ms cadence for a fixed duration.
      - Separate p50/p95/p99/max for each probe class so H1 (global stall)
        can be distinguished from H4 (UI-thread-only slowdown).

.PARAMETER ProbeDurationSec
    Duration of the probe window. Default 15s.

.PARAMETER BurstLines
    Number of PTY output lines to generate in the target. Default 20000.

.PARAMETER Label
    A tag written into the measurement filename (e.g. "pre-mitigation",
    "post-mitigation"). Default "pre".
#>
param(
    [int]$ProbeDurationSec = 15,
    [int]$BurstLines = 20000,
    [string]$Label = "pre"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

$exe = Join-Path $repoRoot "zig-out-winui3\bin\ghostty.exe"
if (-not (Test-Path $exe)) {
    Write-Error "ghostty.exe not found at $exe — run ./build-winui3.sh --release=fast first"
    exit 1
}

# --- Safety: count existing ghostty processes ---
$existing = @(Get-Process ghostty -EA SilentlyContinue)
if ($existing.Count -ge 3) {
    Write-Error "[safety] $($existing.Count) ghostty.exe processes already running; max 3 stress. Kill stale procs first."
    exit 1
}
Write-Host "[safety] $($existing.Count) ghostty already alive — spawning one more for stress." -ForegroundColor Cyan

# --- Spawn the target session ---
$sessionName = "stall-probe-$([int](Get-Date -UFormat %s))"
$env:GHOSTTY_CONTROL_PLANE = "1"
$env:GHOSTTY_SESSION_NAME = $sessionName
$env:GHOSTTY_WINUI3_DISPATCHER_DIAG = "1"
$proc = Start-Process -FilePath $exe -PassThru
$procPid = $proc.Id
Write-Host "[spawn] ghostty pid=$procPid session=$sessionName" -ForegroundColor Green

# Wait for pipe to become connectable.
$pipePath = "\\.\pipe\ghostty-winui3-$sessionName-$procPid"
$wait_start = Get-Date
$pipe_ready = $false
while (((Get-Date) - $wait_start).TotalSeconds -lt 10) {
    try {
        $c = New-Object System.IO.Pipes.NamedPipeClientStream(".", "ghostty-winui3-$sessionName-$procPid", [System.IO.Pipes.PipeDirection]::InOut)
        $c.Connect(100)
        $c.Close()
        $pipe_ready = $true
        break
    } catch { Start-Sleep -Milliseconds 200 }
}
if (-not $pipe_ready) {
    Write-Error "[spawn] pipe $pipePath never became connectable; aborting"
    Stop-Process -Id $procPid -Force -EA SilentlyContinue
    exit 1
}
Write-Host "[spawn] pipe ready: $pipePath" -ForegroundColor Green
Start-Sleep -Milliseconds 500  # let session settle

# --- Probe helper: open client, send command, read response, close. ---
function Invoke-CpProbe {
    param([string]$PipeName, [string]$Command)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $c = New-Object System.IO.Pipes.NamedPipeClientStream(".", $PipeName, [System.IO.Pipes.PipeDirection]::InOut)
        $c.Connect(5000)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Command + "`n")
        $c.Write($bytes, 0, $bytes.Length)
        $c.Flush()
        $buf = New-Object byte[] 4096
        $n = $c.Read($buf, 0, $buf.Length)
        $c.Close()
        $sw.Stop()
        return [PSCustomObject]@{
            ok       = $true
            latency  = $sw.Elapsed.TotalMilliseconds
            response = [System.Text.Encoding]::UTF8.GetString($buf, 0, [math]::Max(0, $n)).Trim()
        }
    } catch {
        $sw.Stop()
        return [PSCustomObject]@{
            ok       = $false
            latency  = $sw.Elapsed.TotalMilliseconds
            response = $_.Exception.Message
        }
    }
}

$pipeNameShort = "ghostty-winui3-$sessionName-$procPid"

# --- Pre-burst sanity: capture pane to see what shell (if any) is running ---
$capRes = Invoke-CpProbe -PipeName $pipeNameShort -Command "CAPTURE_PANE"
$capPreview = if ($capRes.response.Length -gt 200) { $capRes.response.Substring(0,200) } else { $capRes.response }
Write-Host "[sanity] CAPTURE_PANE (first 200b): $capPreview"

# --- Start the PTY-output burst via raw pipe INPUT command ---
# Protocol: INPUT|<from>|<base64(payload)>\n (see vendor/zig-control-plane/src/protocol.zig:153).
# Issue #214 symptom source is a shell-agnostic high-rate writer. Try three
# payloads in sequence so we exercise cmd.exe / powershell / pwsh whichever is
# actually the session shell.
$payloads = @(
    "echo burst-start`r",
    "for /L %i in (1,1,$BurstLines) do @echo t_%i`r",                                 # cmd.exe
    "1..$BurstLines | % { Write-Host ""t`$_"" }`r",                                   # powershell/pwsh
    "echo burst-end`r"
)
foreach ($p in $payloads) {
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($p))
    $r = Invoke-CpProbe -PipeName $pipeNameShort -Command ("INPUT|repro|" + $b64)
    Write-Host "[burst] INPUT ok=$($r.ok) resp=$($r.response.Trim())  payload_head='$($p.Substring(0, [math]::Min(40, $p.Length)))'"
    Start-Sleep -Milliseconds 50
}

# Brief settle + capture again so we can see if output is flowing
Start-Sleep -Seconds 1
$capRes2 = Invoke-CpProbe -PipeName $pipeNameShort -Command "CAPTURE_PANE"
$capPreview2 = if ($capRes2.response.Length -gt 300) { $capRes2.response.Substring(0,300) } else { $capRes2.response }
Write-Host "[sanity] post-burst CAPTURE_PANE (first 300b): $capPreview2"

# --- Probe loop ---
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$measFile = Join-Path $repoRoot ".dispatch/dispatcher-stall-measurements-$Label-$timestamp.log"
New-Item -ItemType File -Path $measFile -Force | Out-Null
"# repro-dispatcher-stall label=$Label pid=$procPid session=$sessionName burst_lines=$BurstLines duration_s=$ProbeDurationSec" | Out-File $measFile -Append -Encoding utf8
"# t_rel_ms,probe_kind,ok,latency_ms" | Out-File $measFile -Append -Encoding utf8

$start = Get-Date
$probe_results = @()
while (((Get-Date) - $start).TotalSeconds -lt $ProbeDurationSec) {
    $t_rel = ((Get-Date) - $start).TotalMilliseconds
    # Lock-free read: STATE
    $r1 = Invoke-CpProbe -PipeName $pipeNameShort -Command "STATE"
    $line = "{0},STATE,{1},{2:F2}" -f ([int]$t_rel), ([int]$r1.ok), $r1.latency
    $line | Out-File $measFile -Append -Encoding utf8
    $probe_results += [PSCustomObject]@{ kind = "STATE"; ok = $r1.ok; latency = $r1.latency }
    # UI-thread mutation: empty INPUT (just the command). Actually INPUT always
    # requires text=... so use a benign SEND_KEYS probe instead.
    $t_rel2 = ((Get-Date) - $start).TotalMilliseconds
    $r2 = Invoke-CpProbe -PipeName $pipeNameShort -Command "CAPABILITIES"
    $line2 = "{0},CAPABILITIES,{1},{2:F2}" -f ([int]$t_rel2), ([int]$r2.ok), $r2.latency
    $line2 | Out-File $measFile -Append -Encoding utf8
    $probe_results += [PSCustomObject]@{ kind = "CAPABILITIES"; ok = $r2.ok; latency = $r2.latency }
    Start-Sleep -Milliseconds 100
}

# --- Summary ---
function Summarize {
    param($results)
    if ($results.Count -eq 0) { return "no samples" }
    $okres = $results | Where-Object { $_.ok }
    $count = $results.Count
    $ok_count = $okres.Count
    if ($ok_count -eq 0) { return "all_failed ($count samples)" }
    $lats = $okres | ForEach-Object { $_.latency } | Sort-Object
    $p50 = $lats[[int]($ok_count * 0.50)]
    $p95 = $lats[[int]($ok_count * 0.95)]
    $p99 = $lats[[int]($ok_count * 0.99)]
    $max = $lats[-1]
    return "count=$count ok=$ok_count p50=$([int]$p50) p95=$([int]$p95) p99=$([int]$p99) max=$([int]$max) (ms)"
}
$state_results = $probe_results | Where-Object { $_.kind -eq "STATE" }
$caps_results = $probe_results | Where-Object { $_.kind -eq "CAPABILITIES" }
$summary_state = Summarize $state_results
$summary_caps = Summarize $caps_results
$summary_line = "# SUMMARY STATE: $summary_state`n# SUMMARY CAPABILITIES: $summary_caps"
$summary_line | Out-File $measFile -Append -Encoding utf8
Write-Host "[summary] STATE: $summary_state" -ForegroundColor Cyan
Write-Host "[summary] CAPABILITIES: $summary_caps" -ForegroundColor Cyan

# --- Copy the DIAG log to .dispatch for archival ---
$diagSrc = Join-Path $env:LOCALAPPDATA "ghostty\dispatcher-stall-diag-$procPid.log"
if (Test-Path $diagSrc) {
    $diagDst = Join-Path $repoRoot ".dispatch/dispatcher-stall-diag-$Label-$timestamp-pid$procPid.log"
    Copy-Item $diagSrc $diagDst
    Write-Host "[diag] copied to $diagDst" -ForegroundColor Cyan
} else {
    Write-Host "[diag] source $diagSrc missing (env var not set at spawn?)" -ForegroundColor Yellow
}

Write-Host "[done] measurements at $measFile" -ForegroundColor Green
Write-Host "[cleanup] terminating ghostty pid=$procPid"
Stop-Process -Id $procPid -Force -EA SilentlyContinue
Start-Sleep -Seconds 1
$residual = @(Get-Process -Id $procPid -EA SilentlyContinue)
if ($residual.Count -gt 0) {
    Write-Host "[cleanup] process did not exit; manual cleanup needed" -ForegroundColor Red
}
