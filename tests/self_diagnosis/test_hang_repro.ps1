#Requires -Version 5.1
<#
.SYNOPSIS
    Hang reproduction script for Issue #139: multi-instance hang under load.

.DESCRIPTION
    Launches 4 ghostty instances simultaneously and applies concurrent stress:
      - PING/TAIL over CP pipes every 10 seconds
      - SetWindowPos resize every 5 seconds
    If SetWindowPos does not return within 3 seconds, declares a hang and
    captures thread-level diagnostics.

    No mouse input (CLAUDE.md compliance). All interaction via SetWindowPos
    and named-pipe CP protocol.

.NOTES
    Run: .\test_hang_repro.ps1 [-Duration 120] [-Instances 4]
    Requires ghostty built with GHOSTTY_CONTROL_PLANE=1.
    Log written to tests/self_diagnosis/hang_repro_<timestamp>.log
#>

param(
    [int]$Duration = 120,
    [int]$Instances = 4
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$script:RepoRoot   = (Resolve-Path "$PSScriptRoot\..\..").Path
$script:GhosttyExe = Join-Path $RepoRoot "zig-out-winui3\bin\ghostty.exe"
$script:SessionDir = Join-Path $env:LOCALAPPDATA "ghostty\control-plane\winui3\sessions"
$script:LogFile    = Join-Path $PSScriptRoot "hang_repro_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$script:HangCount  = 0
$script:PingOK     = 0
$script:PingFail   = 0
$script:ResizeOK   = 0
$script:ResizeSlow = 0

# Win32 API: SetWindowPos + GetWindowRect (no mouse)
Add-Type @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

public class Win32Hang {
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

# ============================================================
# Logging
# ============================================================

function Log([string]$msg) {
    $ts = Get-Date -Format "HH:mm:ss.fff"
    $line = "[$ts] $msg"
    Write-Host $line
    Add-Content -Path $script:LogFile -Value $line
}

# ============================================================
# CP pipe communication
# ============================================================

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

# ============================================================
# Session discovery
# ============================================================

function Find-Sessions {
    $result = @()
    if (-not (Test-Path $script:SessionDir)) { return $result }
    $files = Get-ChildItem $script:SessionDir -Filter "*.json" -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        try {
            $json = Get-Content $f.FullName -Raw | ConvertFrom-Json
            $pipeName = $json.pipe_name
            if (-not $pipeName) { $pipeName = $json.pipeName }
            $pid = $json.pid
            if (-not $pid) { $pid = $json.PID }
            if ($pipeName) {
                $result += @{
                    PipeName = $pipeName
                    PID      = [int]$pid
                    File     = $f.FullName
                }
            }
        } catch { }
    }
    return $result
}

# ============================================================
# Instance management
# ============================================================

function Start-GhosttyInstances([int]$count) {
    $procs = @()
    $env:GHOSTTY_CONTROL_PLANE = "1"

    for ($i = 0; $i -lt $count; $i++) {
        $proc = Start-Process -FilePath $script:GhosttyExe -PassThru -ErrorAction SilentlyContinue
        if ($proc) {
            $procs += $proc
            Log "Launched ghostty #$($i+1) PID=$($proc.Id)"
        } else {
            Log "WARN: Failed to launch ghostty #$($i+1)"
        }
        # Stagger launches to avoid resource contention
        Start-Sleep -Milliseconds 500
    }

    # Wait for CP sessions to appear
    Log "Waiting for $count CP sessions to register..."
    $deadline = (Get-Date).AddSeconds(20)
    $sessions = @()
    while ((Get-Date) -lt $deadline) {
        $sessions = Find-Sessions
        $alive = @()
        foreach ($s in $sessions) {
            $ping = Send-CP $s.PipeName "PING" 2000
            if ($ping -match "PONG") { $alive += $s }
        }
        if ($alive.Count -ge $count) {
            Log "All $count sessions responsive"
            return @{ Procs = $procs; Sessions = $alive }
        }
        Start-Sleep -Seconds 1
    }

    Log "WARN: Only $($alive.Count)/$count sessions responsive after 20s"
    return @{ Procs = $procs; Sessions = $alive }
}

function Stop-GhosttyInstances($procs) {
    foreach ($proc in $procs) {
        if (-not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            Log "Killed ghostty PID=$($proc.Id)"
        }
    }
}

# ============================================================
# Hang detection via timed SetWindowPos
# ============================================================

function Test-Resize([System.Diagnostics.Process]$proc, [int]$timeoutMs = 3000) {
    $hwnd = $proc.MainWindowHandle
    if ($hwnd -eq [IntPtr]::Zero -or -not [Win32Hang]::IsWindow($hwnd)) {
        return @{ OK = $false; Reason = "no_hwnd"; ElapsedMs = 0 }
    }

    $rect = New-Object Win32Hang+RECT
    [Win32Hang]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
    $w = $rect.Right - $rect.Left
    $h = $rect.Bottom - $rect.Top

    # Alternate between slightly larger and slightly smaller
    $newW = if ($w -gt 900) { $w - 50 } else { $w + 50 }
    $newH = if ($h -gt 600) { $h - 30 } else { $h + 30 }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # Run SetWindowPos in a job to enforce timeout
    $job = Start-Job -ScriptBlock {
        param($hwndLong, $newW, $newH)
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class SWP {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
        int X, int Y, int cx, int cy, uint uFlags);
}
"@
        $h = [IntPtr]::new($hwndLong)
        [SWP]::SetWindowPos($h, [IntPtr]::Zero, 0, 0, $newW, $newH, 0x0006) # NOMOVE | NOZORDER
    } -ArgumentList $hwnd.ToInt64(), $newW, $newH

    $completed = Wait-Job $job -Timeout ([math]::Ceiling($timeoutMs / 1000))
    $sw.Stop()

    if (-not $completed) {
        # Job did not complete in time → HANG
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        return @{ OK = $false; Reason = "timeout"; ElapsedMs = $sw.ElapsedMilliseconds }
    }

    Remove-Job $job -Force -ErrorAction SilentlyContinue
    return @{ OK = $true; Reason = "ok"; ElapsedMs = $sw.ElapsedMilliseconds }
}

# ============================================================
# Thread dump on hang
# ============================================================

function Get-ThreadDump([int]$pid) {
    $dump = @()
    $dump += "=== Thread dump for PID $pid at $(Get-Date -Format 'HH:mm:ss.fff') ==="

    try {
        $proc = Get-Process -Id $pid -ErrorAction Stop
        $dump += "Process: $($proc.ProcessName) HandleCount=$($proc.HandleCount) Threads=$($proc.Threads.Count)"
        $dump += "WorkingSet: $([math]::Round($proc.WorkingSet64/1MB, 1)) MB"
        $dump += ""

        $threads = $proc.Threads | Sort-Object -Property TotalProcessorTime -Descending -ErrorAction SilentlyContinue
        $i = 0
        foreach ($thr in $threads) {
            $i++
            $state = try { $thr.ThreadState } catch { "Unknown" }
            $waitReason = try { if ($state -eq "Wait") { $thr.WaitReason } else { "-" } } catch { "-" }
            $cpu = try { $thr.TotalProcessorTime.TotalMilliseconds } catch { 0 }
            $startAddr = try { "0x{0:X}" -f $thr.StartAddress.ToInt64() } catch { "?" }
            $dump += "  Thread[$i] ID=$($thr.Id) State=$state WaitReason=$waitReason CPU=${cpu}ms Start=$startAddr"
            if ($i -ge 30) {
                $dump += "  ... ($($threads.Count - 30) more threads)"
                break
            }
        }
    } catch {
        $dump += "ERROR getting thread info: $($_.Exception.Message)"
    }

    # Try procdump if available (produces minidump file)
    $procdump = Get-Command "procdump.exe" -ErrorAction SilentlyContinue
    if ($procdump) {
        $dumpFile = Join-Path $PSScriptRoot "hang_dump_${pid}_$(Get-Date -Format 'HHmmss').dmp"
        $dump += ""
        $dump += "Attempting procdump -ma $pid $dumpFile ..."
        try {
            $pdResult = & procdump.exe -ma -accepteula $pid $dumpFile 2>&1
            $dump += "procdump result: $($pdResult | Out-String)"
        } catch {
            $dump += "procdump failed: $($_.Exception.Message)"
        }
    } else {
        $dump += "(procdump not found in PATH — thread state above is the best we have)"
    }

    return $dump -join "`n"
}

# ============================================================
# Main stress loop
# ============================================================

try {
    Log "=== Hang reproduction test (Issue #139) ==="
    Log "Instances: $Instances  Duration: ${Duration}s  Log: $script:LogFile"
    Log ""

    if (-not (Test-Path $script:GhosttyExe)) {
        Log "ABORT: ghostty.exe not found at $script:GhosttyExe"
        exit 1
    }

    $state = Start-GhosttyInstances $Instances
    $procs = $state.Procs
    $sessions = $state.Sessions

    if ($sessions.Count -eq 0) {
        Log "ABORT: No responsive sessions"
        Stop-GhosttyInstances $procs
        exit 1
    }

    Log ""
    Log "Starting stress loop for ${Duration}s..."
    Log "  Resize every 5s per instance (SetWindowPos with 3s timeout)"
    Log "  CP PING+TAIL every 10s per instance"
    Log ""

    $startTime = Get-Date
    $endTime = $startTime.AddSeconds($Duration)
    $lastPing = (Get-Date).AddSeconds(-100)   # Force immediate first ping
    $lastResize = (Get-Date).AddSeconds(-100)  # Force immediate first resize
    $iteration = 0

    while ((Get-Date) -lt $endTime) {
        $iteration++
        $now = Get-Date

        # Check for crashed instances
        $aliveProcs = @()
        foreach ($p in $procs) {
            if (-not $p.HasExited) {
                $aliveProcs += $p
            } else {
                Log "WARN: ghostty PID=$($p.Id) exited (code=$($p.ExitCode))"
            }
        }
        if ($aliveProcs.Count -eq 0) {
            Log "ABORT: All ghostty instances have exited"
            break
        }

        # CP PING + TAIL every 10 seconds
        if (($now - $lastPing).TotalSeconds -ge 10) {
            $lastPing = $now
            foreach ($s in $sessions) {
                $ping = Send-CP $s.PipeName "PING" 3000
                if ($ping -match "PONG") {
                    $script:PingOK++
                } else {
                    $script:PingFail++
                    Log "PING FAIL pipe=$($s.PipeName) response=$ping"
                }

                $tail = Send-CP $s.PipeName "TAIL|agent-deck|20" 3000
                if ($tail -match "^OK\|" -or $tail -match "^ERR\|") {
                    # Expected response format
                } else {
                    Log "TAIL unexpected: pipe=$($s.PipeName) response=$($tail | Select-Object -First 1)"
                }
            }
        }

        # SetWindowPos resize every 5 seconds
        if (($now - $lastResize).TotalSeconds -ge 5) {
            $lastResize = $now
            foreach ($p in $aliveProcs) {
                $result = Test-Resize $p 3000
                if ($result.OK) {
                    $script:ResizeOK++
                } elseif ($result.Reason -eq "timeout") {
                    $script:ResizeSlow++
                    $script:HangCount++
                    Log "*** HANG DETECTED *** PID=$($p.Id) SetWindowPos did not return in $($result.ElapsedMs)ms"

                    # Capture thread dump
                    $dump = Get-ThreadDump $p.Id
                    Log $dump
                    Add-Content -Path $script:LogFile -Value ""
                    Add-Content -Path $script:LogFile -Value $dump
                    Add-Content -Path $script:LogFile -Value ""
                } elseif ($result.Reason -eq "no_hwnd") {
                    # Window not yet visible or process exiting — skip
                } else {
                    Log "Resize issue PID=$($p.Id): $($result.Reason) (${($result.ElapsedMs)}ms)"
                }
            }
        }

        Start-Sleep -Seconds 1
    }

    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)

    Log ""
    Log "=== Results ==="
    Log "Duration: ${elapsed}s"
    Log "Instances launched: $Instances"
    Log "Ping OK/Fail: $($script:PingOK)/$($script:PingFail)"
    Log "Resize OK/Slow: $($script:ResizeOK)/$($script:ResizeSlow)"
    Log "Hangs detected: $($script:HangCount)"
    Log ""

    if ($script:HangCount -gt 0) {
        Log "RESULT: HANG REPRODUCED ($($script:HangCount) times)"
        Log "Thread dumps saved to $script:LogFile"
    } else {
        Log "RESULT: NO HANG (clean run)"
    }

} finally {
    Log "Cleaning up..."
    Stop-GhosttyInstances $procs
    Log "Done. Full log: $script:LogFile"
}
