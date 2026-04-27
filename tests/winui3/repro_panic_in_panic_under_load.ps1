# Repro for #240: panic-in-panic under sustained CP poll + text-flood load
#
# Origin: 2026-04-27 12:59:14 simultaneous death of ghostty PIDs 37564 + 42852
# after ~8 minutes hosting parallel Codex + Gemini agent workloads. WER captured
# 21 ghostty crashes in 2 hours, all at offset 0x248b4e (= std.posix.abort,
# fault offset deterministic). Stack reconstruction from
# %USERPROFILE%\AppData\Local\CrashDumps\ghostty.exe.68932.dmp shows:
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
# === HARDENING HISTORY (2026-04-27 PM) ===
#
# Baseline (initial test): 4 pollers @ 5 Hz + text-flood every 5s
#   Result: 0 BUSY, 0 dumps in 3 min. INSUFFICIENT to repro.
#   Discovery: BUSY events DID happen during baseline run, but on OTHER
#   sessions (ghostty-35640) — the test only counted its own pid. After
#   widening the scope, baseline still under-trips because its workload is
#   too light: pure pipe traffic doesn't load the renderer mutex enough
#   for tryLock contention. The original incident was driven by the SHELL
#   inside the session writing thousands of lines/sec (Gemini doing
#   `zig test`, `dir /S`), which is what locks the renderer.
#
# Approach 2 (current): Inject SHELL workload via `deckpilot send`.
#   - Multi-session (-Sessions N): launch N ghostty processes in parallel.
#   - Per-session SHELL flooder: send `dir /S C:\Users\...\src` (~10K lines)
#     every 2s, plus a fast CMD `for /L` echo loop in the background.
#   - High-Hz pollers: 4 pollers × 20 Hz = 80 Hz aggregate per session.
#   - Track BUSY events across ALL sessions, not just one pid.
#
# Reproducible signature (when triggered on this build):
#   - >= 1 ghostty.exe.<pid>.dmp dump in CrashDumps/
#   - OR >= N_BUSY_THRESHOLD `BUSY|renderer_locked` events in daemon log
#     during the run window (after baseline offset).
#   - OR >= 1 session disappearance (process exit) before deadline.
#
# Empirical pass/fail boundary: TBD by run. The test exits FAIL if any of
# the three signatures fire; otherwise PASS.
#
# Run:
#   pwsh -NoProfile -File tests\winui3\repro_panic_in_panic_under_load.ps1
#   pwsh -NoProfile -File tests\winui3\repro_panic_in_panic_under_load.ps1 -Quick
#   pwsh -NoProfile -File tests\winui3\repro_panic_in_panic_under_load.ps1 -Sessions 4 -PollHz 20
#
# Debug knob: -BaselineOnly skips shell injection (= old test shape).

[CmdletBinding()]
param(
    [int]$DurationMinutes = 15,
    [int]$Sessions = 2,
    [int]$ConcurrentPollers = 4,
    [int]$PollHz = 20,
    [int]$BusyThreshold = 5,
    [switch]$Quick,
    [switch]$BaselineOnly
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$exe = Join-Path $repoRoot 'zig-out-winui3\bin\ghostty.exe'
$srcDir = Join-Path $repoRoot 'src'
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

# Cleanup-orphan helper - kill stray ghostty.exe spawned by THIS run only.
#
# IMPORTANT (2026-04-27 self-kill incident): An earlier version called this
# with `-KeepPids @()` which classified *every* ghostty in the system as
# orphan, including the host session that was running the test under
# Gemini/Codex. That caused an 11-minute Gemini session to die at the end
# of the run (no crash, just Stop-Process from this very script). Always
# restrict cleanup to processes started by *this* test run.
function Stop-RunGhostty {
    param([int[]]$RunPids)
    foreach ($p in $RunPids) {
        $live = Get-Process -Id $p -ErrorAction SilentlyContinue
        if ($live) {
            Log "cleanup: stopping run ghostty pid=$p"
            Stop-Process -Id $p -Force -ErrorAction SilentlyContinue
        }
    }
}

Log "repro-start exe=$exe duration=${DurationMinutes}min sessions=$Sessions pollers=$ConcurrentPollers hz=$PollHz baselineOnly=$BaselineOnly"

# Snapshot pre-existing dumps so we can detect new ones
$preDumps = @(Get-ChildItem $dumpDir -Filter 'ghostty.exe.*.dmp' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
Log "pre-existing dumps: $($preDumps.Count)"

# Track which dumps are NEW (created during this run) - by mtime
$runStart = Get-Date

# Launch N ghostty sessions, capture all PIDs
$ghProcs = @()
$ghPids = @()
for ($s = 1; $s -le $Sessions; $s++) {
    # Minimized so the test sessions don't steal the user's foreground
    # focus during the run. UIA / CP pipe paths still work normally
    # against a minimized HWND.
    $proc = Start-Process -FilePath $exe -PassThru -WindowStyle Minimized
    $ghProcs += $proc
    $ghPids += $proc.Id
    Log "launched ghostty session #$s pid=$($proc.Id)"
    Start-Sleep -Seconds 3
}
Start-Sleep -Seconds 3
foreach ($p in $ghProcs) {
    if ($p.HasExited) { throw "ghostty pid=$($p.Id) exited within startup — broken build?" }
}
$sessionNames = $ghPids | ForEach-Object { "ghostty-$_" }

# Background-job arrays for cleanup
$pollers = @()
$flooders = @()

# Spawn concurrent pollers per session
foreach ($sess in $sessionNames) {
    for ($i = 1; $i -le $ConcurrentPollers; $i++) {
        $sb = {
            param($sess, $hz, $deadline)
            $sleepMs = [int](1000 / $hz)
            while ((Get-Date) -lt $deadline) {
                & deckpilot show $sess --tail 5 *> $null
                Start-Sleep -Milliseconds $sleepMs
            }
        }
        $pollers += Start-Job -ScriptBlock $sb -ArgumentList $sess, $PollHz, $deadline
    }
}
Log "spawned $($pollers.Count) pollers ($ConcurrentPollers per session × $Sessions sessions = $($pollers.Count) total, $PollHz Hz each = $($PollHz * $pollers.Count) Hz aggregate)"

if (-not $BaselineOnly) {
    # SHELL WORKLOAD: inside each session, kick off (a) infinite echo loop
    # in the foreground shell + (b) periodic `dir /S` flood. The shell-side
    # writes are what actually load the renderer mutex (vs. CP pipe traffic
    # which doesn't touch it).
    foreach ($sess in $sessionNames) {
        # Bootstrap: start a CMD echo loop that runs forever (until the
        # session dies or test ends). Approach 2 from the brief.
        # We use a short CMD one-liner so a single `deckpilot send` kicks it.
        $bootstrapCmd = "for /L %i in (1,1,99999999) do @echo flood-line-%i payload-text-keep-renderer-busy-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        & deckpilot send $sess $bootstrapCmd *> $null
        Log ("session=" + $sess + ": kicked echo flooder")
        Start-Sleep -Milliseconds 200

        # Periodic `dir /S` injection - sends every 2s. Each `dir /S` of
        # the src tree emits ~10K lines, hammering the renderer hard.
        $flooderSb = {
            param($sess, $deadline, $srcDir)
            while ((Get-Date) -lt $deadline) {
                # Two parallel pressures:
                #  a) `dir /S` against the ghostty src tree (~10K lines text)
                #  b) `dir /S` against zig-out-winui3 (mass binary listing)
                & deckpilot send $sess "dir /S `"$srcDir`"" *> $null
                Start-Sleep -Seconds 2
            }
        }
        $flooders += Start-Job -ScriptBlock $flooderSb -ArgumentList $sess, $deadline, $srcDir
    }
    Log "spawned $($flooders.Count) shell flooders (dir /S every 2s per session)"

    # Additional: 50Hz `deckpilot show` burst to add UI-thread pressure
    # via cross-callback registration (matches original incident shape
    # where 2 ghostty processes were registered for cross-callbacks).
    $burstSb = {
        param($sessions, $deadline)
        while ((Get-Date) -lt $deadline) {
            foreach ($s in $sessions) {
                & deckpilot show $s --tail 1 *> $null
            }
            Start-Sleep -Milliseconds 20  # ~50Hz across N sessions
        }
    }
    $burstJob = Start-Job -ScriptBlock $burstSb -ArgumentList $sessionNames, $deadline
    $pollers += $burstJob
    Log "spawned 50Hz cross-session burst poller"
} else {
    Log "baseline-only mode: no shell injection, no burst pollers"
}

# Monitor
$busyCount = 0
$busyPerSession = @{}
foreach ($s in $sessionNames) { $busyPerSession[$s] = 0 }
$daemonLog = "$env:LOCALAPPDATA\Temp\deckpilot-daemon.log"
$baselineOffset = if (Test-Path $daemonLog) { (Get-Item $daemonLog).Length } else { 0 }
Log "daemon-log baseline offset=$baselineOffset"

$failReason = $null
$testEndedEarly = $false

while ((Get-Date) -lt $deadline) {
    # Check all sessions alive
    foreach ($p in $ghProcs) {
        $live = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
        if (-not $live) {
            $elapsed = (New-TimeSpan -Start $runStart -End (Get-Date)).ToString()
            $failReason = "FAIL pid=$($p.Id) disappeared after $elapsed"
            Log $failReason
            $testEndedEarly = $true
            break
        }
    }
    if ($testEndedEarly) { break }

    # Check daemon log delta for new BUSY|renderer_locked across ALL test sessions
    if (Test-Path $daemonLog) {
        $current = (Get-Item $daemonLog).Length
        if ($current -gt $baselineOffset) {
            $sliceBytes = [Math]::Min($current - $baselineOffset, 4194304)
            try {
                $stream = [System.IO.File]::Open($daemonLog, 'Open', 'Read', 'ReadWrite')
                $stream.Seek($baselineOffset, 'Begin') | Out-Null
                $buf = New-Object byte[] $sliceBytes
                $stream.Read($buf, 0, $sliceBytes) | Out-Null
                $stream.Close()
                $slice = [System.Text.Encoding]::UTF8.GetString($buf)
                # Match BUSY|renderer_locked for any of OUR session names
                foreach ($sname in $sessionNames) {
                    $rx = "$([regex]::Escape($sname)).*BUSY\|renderer_locked"
                    $m = ([regex]::Matches($slice, $rx)).Count
                    if ($m -gt 0) {
                        $busyPerSession[$sname] += $m
                        $busyCount += $m
                    }
                }
                if ($busyCount -gt 0 -and ($busyCount % 5 -eq 0 -or $busyCount -le 5)) {
                    $perSess = ($busyPerSession.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '
                    Log "renderer_locked total=$busyCount [$perSess]"
                }
                $baselineOffset = $current
            } catch {
                Log "daemon-log read error: $_"
            }
        }
    }

    # Check for new dumps for ANY of our session pids
    foreach ($p in $ghProcs) {
        $dumpPath = Join-Path $dumpDir "ghostty.exe.$($p.Id).dmp"
        if (Test-Path $dumpPath) {
            $failReason = "FAIL crash dump appeared for pid=$($p.Id): $dumpPath"
            Log $failReason
            $testEndedEarly = $true
            break
        }
    }
    if ($testEndedEarly) { break }

    # Note: BUSY count is informational only after #242 circuit breaker.
    # The breaker fast-fails inbound requests with ERR|BUSY|renderer_locked
    # to keep clients off the renderer mutex during a storm, so BUSY count
    # going high under load is now expected behaviour. The real signals
    # are process disappearance and new crash dumps (above).

    Start-Sleep -Seconds 2
}

# Cleanup
Log "test-end busyCount=$busyCount endedEarly=$testEndedEarly"
$pollers + $flooders | Stop-Job -PassThru -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue *> $null

foreach ($p in $ghProcs) {
    $live = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
    if ($live) {
        Log "stopping ghostty pid=$($p.Id)"
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
}
Start-Sleep -Seconds 1
# Cleanup only the pids this run launched (do NOT kill arbitrary ghostty
# processes — see Stop-RunGhostty docstring re: 2026-04-27 self-kill).
Stop-RunGhostty -RunPids $ghPids

# Verdict
$newDumps = @()
foreach ($p in $ghProcs) {
    $d = Get-ChildItem $dumpDir -Filter "ghostty.exe.$($p.Id).dmp" -ErrorAction SilentlyContinue
    if ($d) { $newDumps += $d }
}
# Also look for any dump created since runStart (catches re-spawned pids)
$recentDumps = @(Get-ChildItem $dumpDir -Filter 'ghostty.exe.*.dmp' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt $runStart -and $preDumps -notcontains $_.Name })

$totalNewDumps = $newDumps.Count + ($recentDumps | Where-Object { $newDumps -notcontains $_ }).Count

if ($totalNewDumps -gt 0 -or $testEndedEarly) {
    $reason = if ($failReason) { $failReason } else { "dumps=$totalNewDumps" }
    Log "VERDICT: FAIL ($reason) busy=$busyCount"
    exit 1
} else {
    Log "VERDICT: PASS (sessions all survived under load) busy=$busyCount dumps=0"
    exit 0
}
