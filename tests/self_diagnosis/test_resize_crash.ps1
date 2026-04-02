#Requires -Version 5.1
<#
.SYNOPSIS
    Regression test for Issue #86: crash during resize + pointer events.

.DESCRIPTION
    Tests the app.resizing guard that prevents ue.focus() from being called
    during window resize operations. Uses SetWindowPos for resize (no mouse).
    Monitors for crashes via process exit and VEH exception logs.

.NOTES
    Requires ghostty running with GHOSTTY_CONTROL_PLANE=1.
    No mouse input used (CLAUDE.md compliance).
    Run: .\test_resize_crash.ps1 [-Attach] [-Iterations 50]
#>

param(
    [switch]$Attach,
    [int]$Iterations = 50
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$script:RepoRoot    = (Resolve-Path "$PSScriptRoot\..\..").Path
$script:GhosttyExe = Join-Path $RepoRoot "zig-out-winui3\bin\ghostty.exe"
$script:SessionDir  = Join-Path $env:LOCALAPPDATA "ghostty\control-plane\winui3\sessions"
$script:Passed      = 0
$script:Failed      = 0
$script:GhosttyProc = $null
$script:PipeName    = $null
$script:Launched    = $false

# Win32 API for SetWindowPos (no mouse needed)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Resize {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
        int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern IntPtr FindWindowW(string lpClassName, string lpWindowName);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left, Top, Right, Bottom;
    }

    public const uint SWP_NOZORDER = 0x0004;
    public const uint SWP_NOACTIVATE = 0x0010;
    public const uint SWP_NOMOVE = 0x0002;
}
"@

function Log([string]$msg) { Write-Host "[resize-test] $msg" }

function Send-CP([string]$cmd) {
    try {
        $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", $script:PipeName, [System.IO.Pipes.PipeDirection]::InOut)
        $pipe.Connect(3000)
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
    $sessions = Get-ChildItem $script:SessionDir -Filter "*.json" -ErrorAction SilentlyContinue
    foreach ($s in $sessions) {
        $json = Get-Content $s.FullName -Raw | ConvertFrom-Json
        $script:PipeName = $json.pipe_name
        if (-not $script:PipeName) { $script:PipeName = $json.pipeName }
        if ($script:PipeName) {
            $ping = Send-CP "PING"
            if ($ping -match "PONG") { return $true }
        }
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

    for ($i = 0; $i -lt 10; $i++) {
        if (Find-Session) {
            Log "Ghostty started (PID=$($script:GhosttyProc.Id), pipe: $script:PipeName)"
            return $true
        }
        Start-Sleep -Seconds 1
    }
    Log "FAIL: Ghostty started but no CP session found"
    return $false
}

function Stop-Ghostty {
    if ($script:Launched -and $script:GhosttyProc -and -not $script:GhosttyProc.HasExited) {
        Stop-Process -Id $script:GhosttyProc.Id -Force -ErrorAction SilentlyContinue
        Log "Ghostty stopped"
    }
}

function Test-Result([string]$name, [bool]$pass, [string]$detail = "") {
    if ($pass) {
        $script:Passed++
        Write-Host "  PASS: $name $detail" -ForegroundColor Green
    } else {
        $script:Failed++
        Write-Host "  FAIL: $name $detail" -ForegroundColor Red
    }
}

function Get-GhosttyHwnd {
    # Find ghostty window by process
    if ($script:GhosttyProc) {
        return $script:GhosttyProc.MainWindowHandle
    }
    # Fallback: find by window title
    $procs = Get-Process -Name "ghostty" -ErrorAction SilentlyContinue
    if ($procs) { return $procs[0].MainWindowHandle }
    return [IntPtr]::Zero
}

# ============================================================
# Main test
# ============================================================
try {
    Log "=== Resize crash regression test (Issue #86) ==="
    Log "Iterations: $Iterations"

    if (-not (Start-Ghostty)) {
        Write-Host "ABORT: Cannot connect to ghostty" -ForegroundColor Red
        exit 1
    }

    # Get window handle
    Start-Sleep -Seconds 1
    $hwnd = Get-GhosttyHwnd
    Test-Result "Window handle found" ($hwnd -ne [IntPtr]::Zero) "hwnd=$hwnd"

    if ($hwnd -eq [IntPtr]::Zero) {
        Log "Cannot proceed without window handle"
        exit 1
    }

    # Get initial window rect
    $rect = New-Object Win32Resize+RECT
    [Win32Resize]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
    $origW = $rect.Right - $rect.Left
    $origH = $rect.Bottom - $rect.Top
    Log "Original window size: ${origW}x${origH}"

    # Test: Rapid resize cycles while sending CP commands
    $rng = New-Object System.Random
    $crashed = $false
    $resizeCount = 0

    for ($i = 0; $i -lt $Iterations; $i++) {
        # Random size delta
        $dw = $rng.Next(-100, 100)
        $dh = $rng.Next(-80, 80)
        $newW = [Math]::Max(400, $origW + $dw)
        $newH = [Math]::Max(300, $origH + $dh)

        # Resize via SetWindowPos (no mouse)
        [Win32Resize]::SetWindowPos($hwnd, [IntPtr]::Zero, 0, 0, $newW, $newH,
            [Win32Resize]::SWP_NOZORDER -bor [Win32Resize]::SWP_NOACTIVATE -bor [Win32Resize]::SWP_NOMOVE) | Out-Null
        $resizeCount++

        # Interleave CP commands during resize (triggers the race condition)
        $ping = Send-CP "PING"
        if ($ping -notmatch "PONG") {
            # Process may have crashed
            if ($script:Launched -and $script:GhosttyProc.HasExited) {
                $crashed = $true
                Log "CRASH detected at iteration $i (exit code: $($script:GhosttyProc.ExitCode))"
                break
            }
        }

        # Brief pause to allow resize processing
        Start-Sleep -Milliseconds 50
    }

    # Restore original size
    [Win32Resize]::SetWindowPos($hwnd, [IntPtr]::Zero, 0, 0, $origW, $origH,
        [Win32Resize]::SWP_NOZORDER -bor [Win32Resize]::SWP_NOACTIVATE -bor [Win32Resize]::SWP_NOMOVE) | Out-Null

    Test-Result "Survived $resizeCount resize cycles" (-not $crashed) ""

    # Verify process still alive
    $alive = $true
    if ($script:Launched) {
        $alive = -not $script:GhosttyProc.HasExited
    } else {
        $finalPing = Send-CP "PING"
        $alive = $finalPing -match "PONG"
    }
    Test-Result "Process alive after resize stress" $alive ""

    # Check for VEH exceptions in debug log
    $logFile = Join-Path $env:LOCALAPPDATA "ghostty\debug.log"
    if (Test-Path $logFile) {
        $logContent = Get-Content $logFile -Tail 200 -ErrorAction SilentlyContinue
        $vehExceptions = ($logContent | Where-Object { $_ -match "VEH|EXCEPTION|ACCESS_VIOLATION" }).Count
        $resizeGuard = ($logContent | Where-Object { $_ -match "skipping focus.*resizing" }).Count
        Test-Result "No VEH exceptions in log" ($vehExceptions -eq 0) "(found: $vehExceptions)"
        if ($resizeGuard -gt 0) {
            Log "  INFO: Resize guard activated $resizeGuard times (Issue #86 fix working)"
        }
    } else {
        Log "  INFO: No debug.log found (expected in non-debug builds)"
    }

    # Summary
    Log ""
    Log "=== Results: $script:Passed passed, $script:Failed failed ==="
}
finally {
    Stop-Ghostty
}
