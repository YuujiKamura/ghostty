#Requires -Version 5.1
<#
.SYNOPSIS
    Thread safety test for CP pipe callbacks after H1 fix (Issue #139).

.DESCRIPTION
    Validates that the SendMessageW dispatch fix for CP read callbacks is
    thread-safe under concurrent load:

    Test 1: Concurrent TAIL/PING from multiple threads
      - Spawns N background jobs, each sending rapid TAIL+PING to the same pipe
      - Verifies no crashes (process alive) and no corrupted responses

    Test 2: TAIL under resize stress
      - One thread sends continuous TAIL requests
      - Main thread sends SetWindowPos resizes every 500ms
      - Verifies SetWindowPos returns within 3 seconds (no UI hang)

    No mouse input (CLAUDE.md compliance).

.NOTES
    Run: .\test_cp_thread_safety.ps1 [-Attach] [-Threads 4] [-Duration 30]
    Requires ghostty running with GHOSTTY_CONTROL_PLANE=1.
#>

param(
    [switch]$Attach,
    [int]$Threads = 4,
    [int]$Duration = 30,
    [ValidateSet('all', 'test1', 'test2')]
    [string]$Mode = 'all'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$script:RepoRoot   = (Resolve-Path "$PSScriptRoot\..\..").Path
$script:GhosttyExe = Join-Path $RepoRoot "zig-out-winui3\bin\ghostty.exe"
$script:SessionDir = Join-Path $env:LOCALAPPDATA "ghostty\control-plane\winui3\sessions"
$script:LogFile    = Join-Path $PSScriptRoot "cp_thread_safety_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$script:RunStartedAt = Get-Date
$script:ArtifactsDir = Join-Path $PSScriptRoot "artifacts\cp-thread-safety\$($script:RunStartedAt.ToString('yyyyMMdd-HHmmss'))"
$script:Passed     = 0
$script:Failed     = 0
$script:GhosttyProc = $null
$script:PipeName   = $null
$script:Launched   = $false

New-Item -ItemType Directory -Path $script:ArtifactsDir -Force | Out-Null

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32TS {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
        int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left, Top, Right, Bottom;
    }

    public const uint SWP_NOZORDER   = 0x0004;
    public const uint SWP_NOACTIVATE = 0x0010;
    public const uint SWP_NOMOVE     = 0x0002;
}
"@

function Log([string]$msg) {
    $ts = Get-Date -Format "HH:mm:ss.fff"
    $line = "[$ts] $msg"
    Write-Host $line
    Add-Content -Path $script:LogFile -Value $line
}

function Test-Result([string]$name, [bool]$pass, [string]$detail = "") {
    if ($pass) {
        $script:Passed++
        Write-Host "  PASS: $name $detail" -ForegroundColor Green
    } else {
        $script:Failed++
        Write-Host "  FAIL: $name $detail" -ForegroundColor Red
    }
    Add-Content -Path $script:LogFile -Value "$(if ($pass) {'PASS'} else {'FAIL'}): $name $detail"
}

function Collect-CrashEvidence([string]$reason) {
    $safeReason = ($reason -replace '[^a-zA-Z0-9_-]', '_')
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $evidencePath = Join-Path $script:ArtifactsDir "crash-evidence-${safeReason}-${stamp}.log"
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("reason=$reason")
    $lines.Add("time=$(Get-Date -Format o)")
    $lines.Add("run_started=$(Get-Date $script:RunStartedAt -Format o)")
    $lines.Add("pipe_name=$($script:PipeName)")
    if ($script:GhosttyProc) {
        $lines.Add("ghostty_pid=$($script:GhosttyProc.Id)")
        $lines.Add("ghostty_has_exited=$($script:GhosttyProc.HasExited)")
        if ($script:GhosttyProc.HasExited) {
            $lines.Add("ghostty_exit_code=$($script:GhosttyProc.ExitCode)")
        }
    }

    $lines.Add("")
    $lines.Add("== recent_application_events ==")
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName = 'Application'
            StartTime = $script:RunStartedAt.AddMinutes(-1)
        } -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ProviderName -in @('Application Error', 'Windows Error Reporting') -or
                $_.Message -match 'ghostty(\.exe)?'
            } |
            Select-Object -First 20

        if ($events) {
            foreach ($ev in $events) {
                $lines.Add("--- event ---")
                $lines.Add("time=$($ev.TimeCreated.ToString('o')) provider=$($ev.ProviderName) id=$($ev.Id) level=$($ev.LevelDisplayName)")
                $msg = ($ev.Message -replace "`r?`n", " ")
                $lines.Add("message=$msg")
            }
        } else {
            $lines.Add("no matching events")
        }
    } catch {
        $lines.Add("event_query_error=$($_.Exception.Message)")
    }

    $debugLog = Join-Path $env:USERPROFILE "ghostty_debug.log"
    $lines.Add("")
    $lines.Add("== ghostty_debug_tail ==")
    if (Test-Path $debugLog) {
        try {
            $tail = Get-Content $debugLog -Tail 200 -ErrorAction SilentlyContinue
            if ($tail) {
                foreach ($t in $tail) { $lines.Add($t) }
            } else {
                $lines.Add("debug log exists but tail empty")
            }
        } catch {
            $lines.Add("debug_tail_error=$($_.Exception.Message)")
        }
    } else {
        $lines.Add("no ghostty_debug.log")
    }

    $lines.Add("")
    $lines.Add("== powershell_jobs ==")
    try {
        $jobs = Get-Job -ErrorAction SilentlyContinue
        if ($jobs) {
            foreach ($j in $jobs) {
                $lines.Add("job id=$($j.Id) state=$($j.State) has_more_data=$($j.HasMoreData)")
            }
        } else {
            $lines.Add("no jobs")
        }
    } catch {
        $lines.Add("job_query_error=$($_.Exception.Message)")
    }

    Set-Content -Path $evidencePath -Value $lines -Encoding UTF8
    Log "Crash evidence written: $evidencePath"
}

function Send-CP([string]$pipeName, [string]$cmd, [int]$timeoutMs = 5000) {
    try {
        $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(
            ".", $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
        $pipe.Connect($timeoutMs)
        $writer = New-Object System.IO.StreamWriter($pipe)
        $reader = New-Object System.IO.StreamReader($pipe)
        $writer.AutoFlush = $true
        $writer.WriteLine($cmd)
        $response = $reader.ReadLine()
        $pipe.Close()
        return $response
    } catch {
        return "ERROR|$($_.Exception.Message)"
    }
}

function Find-Session {
    if (-not (Test-Path $script:SessionDir)) { return $false }
    $sessions = Get-ChildItem $script:SessionDir -Filter "*.session" -ErrorAction SilentlyContinue
    foreach ($s in $sessions) {
        try {
            $kv = @{}
            foreach ($line in (Get-Content $s.FullName -ErrorAction SilentlyContinue)) {
                if ($line -match '^(\w+)=(.*)$') { $kv[$Matches[1]] = $Matches[2] }
            }
            $pipePath = $kv['pipe_path']
            if (-not $pipePath) { $pipePath = $kv['pipe_name'] }
            if ($pipePath) {
                # Strip \\.\pipe\ prefix for NamedPipeClientStream
                $script:PipeName = $pipePath -replace '^\\\\\.\\pipe\\', ''
                $ping = Send-CP $script:PipeName "PING"
                if ($ping -match "PONG") { return $true }
            }
        } catch { }
    }
    return $false
}

function Start-Ghostty {
    if ($Attach) {
        if (Find-Session) {
            Log "Attached to running ghostty (pipe: $script:PipeName)"
            return $true
        }
        Log "FAIL: -Attach specified but no running ghostty found"
        return $false
    }

    $env:GHOSTTY_CONTROL_PLANE = "1"
    $script:GhosttyProc = Start-Process -FilePath $script:GhosttyExe -PassThru -ErrorAction SilentlyContinue
    if (-not $script:GhosttyProc) {
        Log "FAIL: Could not start ghostty"
        return $false
    }
    $script:Launched = $true
    Start-Sleep -Seconds 3

    for ($i = 0; $i -lt 15; $i++) {
        if (Find-Session) {
            Log "Ghostty started (PID=$($script:GhosttyProc.Id), pipe: $script:PipeName)"
            return $true
        }
        Start-Sleep -Seconds 1
    }
    Log "FAIL: Ghostty started but no CP session found after 15s"
    return $false
}

function Stop-Ghostty {
    if ($script:Launched -and $script:GhosttyProc -and -not $script:GhosttyProc.HasExited) {
        Stop-Process -Id $script:GhosttyProc.Id -Force -ErrorAction SilentlyContinue
        Log "Ghostty stopped"
    }
}

function Get-GhosttyHwnd {
    if ($script:GhosttyProc) {
        $h = $script:GhosttyProc.MainWindowHandle
        if ($h -ne [IntPtr]::Zero) { return $h }
    }
    $procs = Get-Process -Name "ghostty" -ErrorAction SilentlyContinue
    if ($procs) { return $procs[0].MainWindowHandle }
    return [IntPtr]::Zero
}

function Test-ProcessAlive {
    if ($script:GhosttyProc -and $script:GhosttyProc.HasExited) { return $false }
    $ping = Send-CP $script:PipeName "PING" 3000
    return ($ping -match "PONG")
}

# ============================================================
# Test 1: Concurrent TAIL/PING from multiple threads
# ============================================================

function Run-Test1 {
    Log ""
    Log "=== Test 1: Concurrent TAIL/PING from $Threads threads for ${Duration}s ==="

    $pipeName = $script:PipeName

    # Each job sends rapid TAIL + PING in a loop
    $jobScript = {
        param($pipeName, $durationSec, $threadId)
        $ok = 0; $fail = 0; $corrupt = 0
        $unexpected = [System.Collections.Generic.List[string]]::new()
        $end = (Get-Date).AddSeconds($durationSec)
        while ((Get-Date) -lt $end) {
            foreach ($cmd in @("PING", "TAIL|agent-deck|20")) {
                try {
                    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(
                        ".", $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
                    $pipe.Connect(3000)
                    $w = New-Object System.IO.StreamWriter($pipe)
                    $r = New-Object System.IO.StreamReader($pipe)
                    $w.AutoFlush = $true
                    $w.WriteLine($cmd)
                    $resp = $r.ReadLine()
                    $pipe.Close()

                    if ($cmd -eq "PING") {
                        if ($resp -match "PONG") { $ok++ }
                        else { $fail++ }
                    } else {
                        # TAIL: expect OK| or ERR| prefix
                        if ($resp -match "^(OK|ERR|TAIL)\|") { $ok++ }
                        elseif ($resp -eq $null) { $fail++ }
                        else {
                            $corrupt++
                            if ($unexpected.Count -lt 5) {
                                $unexpected.Add("cmd=$cmd resp=[$resp]")
                            }
                        }
                    }
                } catch {
                    $fail++
                }
            }
            Start-Sleep -Milliseconds 50
        }
        return @{ ThreadId = $threadId; OK = $ok; Fail = $fail; Corrupt = $corrupt; Unexpected = @($unexpected) }
    }

    $jobs = @()
    for ($i = 0; $i -lt $Threads; $i++) {
        $jobs += Start-Job -ScriptBlock $jobScript -ArgumentList $pipeName, $Duration, $i
    }
    $jobs = @($jobs)

    Log "Launched $Threads background jobs. Waiting ${Duration}s..."

    # Monitor process health while jobs run
    $monitorEnd = (Get-Date).AddSeconds($Duration + 5)
    $crashed = $false
    while ((Get-Date) -lt $monitorEnd) {
        if (-not (Test-ProcessAlive)) {
            $crashed = $true
            Log "*** CRASH: ghostty process died during concurrent TAIL/PING ***"
            Collect-CrashEvidence "test1_concurrent_tail_ping"
            break
        }
        $doneCount = @($jobs | Where-Object { $_.State -eq 'Completed' }).Count
        if ($doneCount -eq $Threads) { break }
        Start-Sleep -Seconds 2
    }

    # Fast-stop any lingering jobs to keep L3 turnaround short.
    $runningJobs = @($jobs | Where-Object { $_.State -eq 'Running' })
    if ($runningJobs.Count -gt 0) {
        foreach ($j in $runningJobs) {
            Stop-Job $j -ErrorAction SilentlyContinue
        }
    }
    $null = Wait-Job -Job $jobs -Timeout 3

    # Collect results without per-job indefinite waits.
    $totalOK = 0; $totalFail = 0; $totalCorrupt = 0
    foreach ($job in $jobs) {
        $result = Receive-Job $job -ErrorAction SilentlyContinue
        if ($result) {
            $totalOK += $result.OK
            $totalFail += $result.Fail
            $totalCorrupt += $result.Corrupt
            Log "  Thread $($result.ThreadId): OK=$($result.OK) Fail=$($result.Fail) Corrupt=$($result.Corrupt)"
            foreach ($u in @($result.Unexpected)) {
                Log "    Unexpected: $u"
            }
        } else {
            if ($job.State -ne 'Completed') {
                Log "  Thread job incomplete: Id=$($job.Id) State=$($job.State)"
                $totalFail += 1
            }
        }
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }

    Log "  Total: OK=$totalOK Fail=$totalFail Corrupt=$totalCorrupt"

    Test-Result "No crash during concurrent access" (-not $crashed)
    Test-Result "No corrupted responses" ($totalCorrupt -eq 0)
    Test-Result "Majority of requests succeeded" ($totalOK -gt ($totalFail * 2)) "($totalOK OK vs $totalFail fail)"
    Test-Result "Process still alive after test" (Test-ProcessAlive)
}

# ============================================================
# Test 2: TAIL under resize stress (UI hang detection)
# ============================================================

function Run-Test2 {
    Log ""
    Log "=== Test 2: TAIL under SetWindowPos resize stress for ${Duration}s ==="

    $hwnd = Get-GhosttyHwnd
    if ($hwnd -eq [IntPtr]::Zero) {
        Test-Result "Window handle found" $false
        return
    }
    Test-Result "Window handle found" $true "hwnd=0x$($hwnd.ToString('X'))"

    $pipeName = $script:PipeName

    # Background job: send TAIL continuously
    $tailJob = Start-Job -ScriptBlock {
        param($pipeName, $durationSec)
        $ok = 0; $fail = 0; $slowMs = 0
        $end = (Get-Date).AddSeconds($durationSec)
        while ((Get-Date) -lt $end) {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(
                    ".", $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
                $pipe.Connect(5000)
                $w = New-Object System.IO.StreamWriter($pipe)
                $r = New-Object System.IO.StreamReader($pipe)
                $w.AutoFlush = $true
                $w.WriteLine("TAIL|agent-deck|40")
                $resp = $r.ReadLine()
                $pipe.Close()
                $sw.Stop()

                if ($resp -match "^(OK|ERR|TAIL)\|") {
                    $ok++
                    if ($sw.ElapsedMilliseconds -gt $slowMs) {
                        $slowMs = $sw.ElapsedMilliseconds
                    }
                } else { $fail++ }
            } catch {
                $sw.Stop()
                $fail++
            }
            Start-Sleep -Milliseconds 100
        }
        return @{ OK = $ok; Fail = $fail; SlowestMs = $slowMs }
    } -ArgumentList $pipeName, $Duration

    # Main thread: SetWindowPos resizes with timing
    $resizeOK = 0
    $resizeSlow = 0
    $worstResizeMs = 0
    $hangDetected = $false
    $endTime = (Get-Date).AddSeconds($Duration)
    $toggle = $true

    while ((Get-Date) -lt $endTime) {
        if (-not (Test-ProcessAlive)) {
            Log "*** CRASH: ghostty died during resize+TAIL stress ***"
            $hangDetected = $true
            Collect-CrashEvidence "test2_resize_tail"
            break
        }

        $rect = New-Object Win32TS+RECT
        [Win32TS]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
        $w = $rect.Right - $rect.Left
        $h = $rect.Bottom - $rect.Top
        if ($toggle) { $w += 30; $h += 20 } else { $w -= 30; $h -= 20 }
        $toggle = -not $toggle

        # Timed resize via background job (3s timeout)
        $resizeJob = Start-Job -ScriptBlock {
            param($hwndLong, $newW, $newH)
            Add-Type @"
using System;
using System.Runtime.InteropServices;
public class SWP2 {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
        int X, int Y, int cx, int cy, uint uFlags);
}
"@
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $h = [IntPtr]::new($hwndLong)
            [SWP2]::SetWindowPos($h, [IntPtr]::Zero, 0, 0, $newW, $newH, 0x0006) | Out-Null
            $sw.Stop()
            return $sw.ElapsedMilliseconds
        } -ArgumentList $hwnd.ToInt64(), $w, $h

        $completed = Wait-Job $resizeJob -Timeout 3
        if (-not $completed) {
            $resizeSlow++
            $hangDetected = $true
            Log "*** HANG: SetWindowPos did not return within 3s (TAIL running concurrently) ***"
            Stop-Job $resizeJob -ErrorAction SilentlyContinue
        } else {
            $ms = Receive-Job $resizeJob -ErrorAction SilentlyContinue
            if ($ms -is [long] -or $ms -is [int]) {
                $resizeOK++
                if ($ms -gt $worstResizeMs) { $worstResizeMs = $ms }
            } else {
                $resizeOK++
            }
        }
        Remove-Job $resizeJob -Force -ErrorAction SilentlyContinue

        Start-Sleep -Milliseconds 500
    }

    # Collect TAIL job results
    $tailDone = Wait-Job $tailJob -Timeout 5
    if (-not $tailDone) {
        Log "  Tail job timeout: Id=$($tailJob.Id) State=$($tailJob.State)"
        Stop-Job $tailJob -ErrorAction SilentlyContinue
    }
    $tailResult = Receive-Job $tailJob -ErrorAction SilentlyContinue
    Remove-Job $tailJob -Force -ErrorAction SilentlyContinue

    if ($tailResult) {
        Log "  TAIL: OK=$($tailResult.OK) Fail=$($tailResult.Fail) SlowestMs=$($tailResult.SlowestMs)"
    }
    Log "  Resize: OK=$resizeOK Slow(>3s)=$resizeSlow WorstMs=$worstResizeMs"

    Test-Result "No UI hang during TAIL+resize" (-not $hangDetected)
    Test-Result "SetWindowPos worst < 3000ms" ($worstResizeMs -lt 3000) "(${worstResizeMs}ms)"
    Test-Result "TAIL requests succeeded" ($tailResult -and $tailResult.OK -gt 0) "($($tailResult.OK) OK)"
    Test-Result "Process still alive" (Test-ProcessAlive)
}

# ============================================================
# Main
# ============================================================

try {
    Log "=== CP Thread Safety Test (Issue #139 H1 fix) ==="
    Log "Threads: $Threads  Duration: ${Duration}s  Mode: $Mode  Log: $script:LogFile"
    Log ""

    if (-not (Test-Path $script:GhosttyExe)) {
        Log "ABORT: ghostty.exe not found at $script:GhosttyExe"
        exit 1
    }

    if (-not (Start-Ghostty)) {
        Write-Host "ABORT: Cannot connect to ghostty" -ForegroundColor Red
        exit 1
    }

    switch ($Mode) {
        'test1' { Run-Test1 }
        'test2' { Run-Test2 }
        default {
            Run-Test1
            Run-Test2
        }
    }

    Log ""
    Log "=== Summary ==="
    Log "Passed: $($script:Passed)  Failed: $($script:Failed)"
    if ($script:Failed -eq 0) {
        Write-Host "ALL TESTS PASSED" -ForegroundColor Green
    } else {
        Write-Host "$($script:Failed) TEST(S) FAILED" -ForegroundColor Red
    }
} finally {
    Stop-Ghostty
    Log "Full log: $script:LogFile"
}
