# Repro for #240: panic-in-panic under sustained CP poll + text-flood load
#
# Origin: 2026-04-27 12:59:14 simultaneous death of ghostty PIDs 37564 + 42852
# after ~8 minutes hosting parallel Codex + Gemini agent workloads. WER captured
# 21 ghostty crashes in 2 hours, all at offset 0x248b4e (= std.posix.abort,
# fault offset deterministic). Stack reconstruction from
# C:\Users\yuuji\AppData\Local\CrashDumps\ghostty.exe.68932.dmp shows:
#
#   abort                          posix.zig:687       (STATUS_BREAKPOINT)
#   handleSegfaultWindowsExtra     debug.zig:1560
#   handleSegfaultWindows          debug.zig:1544
#   OpenFile                       windows.zig:130     <-- segfault here
#   openFileW                      fs/Dir.zig:945
#   openFile                       fs/Dir.zig:821
#   printLineFromFileAnyOs         debug.zig:1185
#   printLineInfo__anon_12029      debug.zig:1176
#   printSourceAtAddress           debug.zig:1123
#   writeStackTraceWindows         debug.zig:1076
#
# Diagnosis: panic-in-panic. Some original panic triggered
# writeStackTraceWindows -> tries to open the .zig source for line context ->
# OpenFile segfaults (0xAA poison on stack frame) -> VEH catches it ->
# abort() -> STATUS_BREAKPOINT. WER reports the breakpoint, not the root panic.
#
# Deckpilot daemon log shows precursor signal: "server: BUSY|renderer_locked"
# fires repeatedly under active load (not pure idle), and process
# disappearance is simultaneous with last BUSY recovery.
#
# This script reproduces the load shape WITHOUT requiring Gemini:
#   - Launch ghostty fully detached, capture PID
#   - Spawn N=4 concurrent deckpilot CP pollers at ~5 Hz each (= 20 Hz aggregate)
#   - Spawn 1 text-flood writer that pipes ~1MB of text into the session at
#     ~50KB/sec to keep the renderer busy
#   - Watch for renderer_locked frequency, pid disappearance, and
#     %LOCALAPPDATA%\CrashDumps\ghostty.exe.<pid>.dmp creation
#   - Cap at 15 minutes of wall time
#
# Pass criteria: ghostty.exe.<pid> survives 15min with renderer_locked count <= 5.
# Fail criteria: process death OR renderer_locked count > 5 OR new crash dump
# created with offset 0x248b4e.
#
# Run:
#   pwsh -NoProfile -File tests\winui3\repro_panic_in_panic_under_load.ps1
#   pwsh -NoProfile -File tests\winui3\repro_panic_in_panic_under_load.ps1 -Quick   # 3min cap

[CmdletBinding()]
param(
    [int]$DurationMinutes = 15,
    [int]$ConcurrentPollers = 4,
    [int]$PollHz = 5,
    [switch]$Quick
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$exe = Join-Path $repoRoot 'zig-out-winui3\bin\ghostty.exe'
$dumpDir = "$env:LOCALAPPDATA\CrashDumps"
$logDir = Join-Path $repoRoot 'notes\2026-04-27-deadlock-audit\repro\runs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

if (-not (Test-Path $exe)) { throw "ghostty.exe not built: $exe" }

if ($Quick) { $DurationMinutes = 3 }
$deadline = (Get-Date).AddMinutes($DurationMinutes)
$runId = (Get-Date).ToString('yyyyMMdd-HHmmss')
$runLog = Join-Path $logDir "run-$runId.log"

function Log {
    param([string]$msg)
    $line = "[$((Get-Date).ToString('HH:mm:ss.fff'))] $msg"
    Add-Content -Path $runLog -Value $line
    Write-Host $line
}

Log "repro-start exe=$exe duration=${DurationMinutes}min pollers=$ConcurrentPollers hz=$PollHz"

# Snapshot pre-existing dumps so we can detect new ones
$preDumps = @(Get-ChildItem $dumpDir -Filter 'ghostty.exe.*.dmp' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
Log "pre-existing dumps: $($preDumps.Count)"

# Launch ghostty fully detached
$proc = Start-Process -FilePath $exe -PassThru -WindowStyle Normal
$ghPid = $proc.Id
Log "launched ghostty pid=$ghPid"
Start-Sleep -Seconds 6
if ($proc.HasExited) { throw "ghostty exited within 6s — broken build?" }

$session = "ghostty-$ghPid"

# Spawn concurrent pollers
$pollers = @()
for ($i = 1; $i -le $ConcurrentPollers; $i++) {
    $sb = {
        param($sess, $hz, $deadline)
        $sleepMs = [int](1000 / $hz)
        while ((Get-Date) -lt $deadline) {
            & deckpilot show $sess --tail 5 *> $null
            Start-Sleep -Milliseconds $sleepMs
        }
    }
    $pollers += Start-Job -ScriptBlock $sb -ArgumentList $session, $PollHz, $deadline
}
Log "spawned $($pollers.Count) pollers"

# Text-flood writer: send a long printf into the session every 5s
$flooder = Start-Job -ScriptBlock {
    param($sess, $deadline)
    $payload = ('lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua ' * 100)
    while ((Get-Date) -lt $deadline) {
        & deckpilot send $sess "echo $payload" *> $null
        Start-Sleep -Seconds 5
    }
} -ArgumentList $session, $deadline
Log "spawned text-flooder"

# Monitor
$busyCount = 0
$daemonLog = "$env:LOCALAPPDATA\Temp\deckpilot-daemon.log"
$baselineOffset = if (Test-Path $daemonLog) { (Get-Item $daemonLog).Length } else { 0 }
Log "daemon-log baseline offset=$baselineOffset"

while ((Get-Date) -lt $deadline) {
    # Check process alive
    $live = Get-Process -Id $ghPid -ErrorAction SilentlyContinue
    if (-not $live) {
        Log "FAIL pid=$ghPid disappeared after $((New-TimeSpan -Start $proc.StartTime -End (Get-Date)).ToString())"
        break
    }

    # Check daemon log delta for new BUSY|renderer_locked
    if (Test-Path $daemonLog) {
        $current = (Get-Item $daemonLog).Length
        if ($current -gt $baselineOffset) {
            $sliceBytes = [Math]::Min($current - $baselineOffset, 1048576)
            $stream = [System.IO.File]::Open($daemonLog, 'Open', 'Read', 'ReadWrite')
            $stream.Seek($baselineOffset, 'Begin') | Out-Null
            $buf = New-Object byte[] $sliceBytes
            $stream.Read($buf, 0, $sliceBytes) | Out-Null
            $stream.Close()
            $slice = [System.Text.Encoding]::UTF8.GetString($buf)
            $busyMatches = ([regex]::Matches($slice, "ghostty-$ghPid.*BUSY\|renderer_locked")).Count
            if ($busyMatches -gt 0) {
                $busyCount += $busyMatches
                Log "renderer_locked count=$busyCount (+$busyMatches)"
            }
            $baselineOffset = $current
        }
    }

    # Check for new dumps
    $curDumps = @(Get-ChildItem $dumpDir -Filter "ghostty.exe.$ghPid.dmp" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    if ($curDumps.Count -gt 0) {
        Log "FAIL crash dump appeared: $($curDumps[0])"
        break
    }

    Start-Sleep -Seconds 5
}

# Cleanup
Log "test-end busyCount=$busyCount"
$pollers | Stop-Job -PassThru | Remove-Job -Force *> $null
$flooder | Stop-Job -PassThru | Remove-Job -Force *> $null
$live = Get-Process -Id $ghPid -ErrorAction SilentlyContinue
if ($live) {
    Log "stopping ghostty pid=$ghPid"
    Stop-Process -Id $ghPid -Force -ErrorAction SilentlyContinue
}

# Verdict
$newDumps = @(Get-ChildItem $dumpDir -Filter "ghostty.exe.$ghPid.dmp" -ErrorAction SilentlyContinue)

if ($newDumps.Count -gt 0 -or $busyCount -gt 5) {
    Log "VERDICT: FAIL (busy=$busyCount, dumps=$($newDumps.Count))"
    exit 1
} else {
    Log "VERDICT: PASS (busy=$busyCount, dumps=0)"
    exit 0
}
