<#
.SYNOPSIS
    Regression harness for the `SHELL=/bin/bash.exe` InvalidUtf8 bug.

.DESCRIPTION
    When ghostty.exe is launched with env var SHELL=/bin/bash.exe (inherited
    from bash profiles on Windows), the IO thread fails with error.InvalidUtf8.
    The error message is rendered INSIDE the terminal window via t.printString,
    NOT on stderr, so we detect the bug indirectly by looking for evidence that
    the child subcommand ever got spawned in the stderr debug log.

    Detection rule:
      - stderr contains "shell integration automatically injected"
        or "started subcommand" --> PASS (shell spawn succeeded)
      - absence of "started subcommand" after timeout --> FAIL
        (bug reproduces -- IO thread died before spawning subcommand)

    Two tests per invocation:
      1. SHELL=/bin/bash.exe   -- the bug-trigger path
      2. SHELL unset           -- control (should always PASS)

.PARAMETER Mode
    repro       : expects FAIL on buggy build (verdict=FAIL => exit 0)
    regression  : expects PASS on fixed build (verdict=PASS => exit 0)

.PARAMETER ExpectFail
    If set, forces the bug test expectation to FAIL regardless of Mode.

.PARAMETER ExePath
    Optional override. Defaults to zig-out-winui3\bin\ghostty.exe under repo root.

.PARAMETER TimeoutSec
    Per-test timeout. Default 10.
#>
param(
    [ValidateSet("repro","regression")]
    [string]$Mode = "repro",
    [switch]$ExpectFail,
    [string]$ExePath,
    [int]$TimeoutSec = 10
)

$ErrorActionPreference = "Continue"
$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not $ExePath) {
    $ExePath = Join-Path $repoRoot "zig-out-winui3\bin\ghostty.exe"
}
if (-not (Test-Path $ExePath)) {
    Write-Host "[repro-invalidutf8] ghostty.exe not found at $ExePath -- run ./build-winui3.sh first" -ForegroundColor Red
    exit 2
}

$logDir = Join-Path $repoRoot ".dispatch"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

# --- Win32 window title probe (bonus check) ---
if (-not ("WinProbe" -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinProbe {
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern int GetWindowTextW(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")]
    public static extern int GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
}
"@
}

function Find-WindowTitleForPid {
    param([int]$TargetPid)
    $script:__foundTitle = $null
    $cb = [WinProbe+EnumWindowsProc]{
        param($hwnd, $lparam)
        if (-not [WinProbe]::IsWindowVisible($hwnd)) { return $true }
        [uint32]$wpid = 0
        [void][WinProbe]::GetWindowThreadProcessId($hwnd, [ref]$wpid)
        if ($wpid -eq $TargetPid) {
            $sb = New-Object System.Text.StringBuilder 512
            [void][WinProbe]::GetWindowTextW($hwnd, $sb, $sb.Capacity)
            $t = $sb.ToString()
            if ($t.Length -gt 0 -and -not $script:__foundTitle) {
                $script:__foundTitle = $t
            }
        }
        return $true
    }
    try { [void][WinProbe]::EnumWindows($cb, [IntPtr]::Zero) } catch {}
    return $script:__foundTitle
}

# --- Core test runner ---
function Invoke-GhosttyTest {
    param(
        [string]$Label,
        [hashtable]$ExtraEnv,
        [string[]]$RemoveEnv
    )

    Write-Host ""
    Write-Host "=== [$Label] starting ===" -ForegroundColor Cyan

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $stderrLog = Join-Path $logDir "repro-invalidutf8-$Label-$stamp.stderr.log"
    $stdoutLog = Join-Path $logDir "repro-invalidutf8-$Label-$stamp.stdout.log"
    New-Item -ItemType File -Path $stderrLog -Force | Out-Null
    New-Item -ItemType File -Path $stdoutLog -Force | Out-Null

    # ghostty's WinUI3 runtime calls attachDebugConsole() early in App.init
    # and redirects stderr (via SetStdHandle) to $env:TEMP\ghostty_debug.log.
    # The stderr pipe we redirect via ProcessStartInfo only catches the first
    # ~10 lines before the handle swap. The rest -- including "started
    # subcommand" -- goes to the temp file. We therefore tail that file.
    $debugLog = Join-Path $env:TEMP "ghostty_debug.log"

    # Delete any prior run's log BEFORE spawning, so we don't confuse a
    # previous test's FAIL signal with ours. Retry a few times because the
    # file may still be held by a previous ghostty that hasn't exited yet.
    for ($i = 0; $i -lt 10; $i++) {
        try {
            if (Test-Path $debugLog) { Remove-Item -Path $debugLog -Force -ErrorAction Stop }
            break
        } catch {
            Start-Sleep -Milliseconds 200
        }
    }
    if (Test-Path $debugLog) {
        # Couldn't delete; at least truncate so old content doesn't leak.
        try { Clear-Content $debugLog -ErrorAction Stop } catch {
            Write-Host "[$Label] WARN: could not clear $debugLog -- old content may contaminate detection" -ForegroundColor Yellow
        }
    }

    # Build per-process env via ProcessStartInfo (Start-Process has no -Environment).
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ExePath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $false

    # Copy current env into child starting point, then mutate.
    foreach ($de in [Environment]::GetEnvironmentVariables().GetEnumerator()) {
        $k = [string]$de.Key
        $v = [string]$de.Value
        if (-not [string]::IsNullOrEmpty($k)) {
            $psi.EnvironmentVariables[$k] = $v
        }
    }
    if ($RemoveEnv) {
        foreach ($k in $RemoveEnv) {
            if ($psi.EnvironmentVariables.ContainsKey($k)) {
                [void]$psi.EnvironmentVariables.Remove($k)
            }
        }
    }
    if ($ExtraEnv) {
        foreach ($k in $ExtraEnv.Keys) {
            $psi.EnvironmentVariables[$k] = [string]$ExtraEnv[$k]
        }
    }
    # Deliberately do NOT set GHOSTTY_LOG -- it expects a packed-struct
    # (e.g. "stderr,macos"), not a log level. Default info-level stderr logging
    # already emits "started subcommand" which is what we look for.

    $proc = $null
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
    } catch {
        Write-Host "[$Label] Process.Start failed: $($_.Exception.Message)" -ForegroundColor Red
        return [PSCustomObject]@{
            Label=$Label; Verdict="ERROR"; Reason="spawn failed: $($_.Exception.Message)"
            StderrLog=$stderrLog; WindowTitle=$null; Pid=$null
        }
    }
    $procPid = $proc.Id
    Write-Host "[$Label] spawned pid=$procPid -> stderr=$stderrLog" -ForegroundColor Green

    # Drain stderr in background Runspace-style: spawn a thread via PS jobs is
    # too heavy; instead we poll the child's StandardError StreamReader
    # non-blocking using .Peek() is not available, so use async reads on the
    # underlying BaseStream.
    $errReader = $proc.StandardError
    $outReader = $proc.StandardOutput
    $sbErr = New-Object System.Text.StringBuilder
    $sbOut = New-Object System.Text.StringBuilder

    $errBuf = New-Object char[] 8192
    $outBuf = New-Object char[] 8192
    $errTask = $errReader.ReadAsync($errBuf, 0, $errBuf.Length)
    $outTask = $outReader.ReadAsync($outBuf, 0, $outBuf.Length)

    $verdict = "UNKNOWN"
    $reason = ""
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # When we first saw "started subcommand" the clock starts. If no
    # Invalid/abnormal signal appears within $postSpawnGraceMs after, we call it
    # PASS. This handles Windows cmd.exe where there's no shell-integration
    # line to wait for.
    $postSpawnGraceMs = 2500
    $subcmdSeenAt = $null

    try {
        while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
            if ($null -ne $errTask -and $errTask.IsCompleted) {
                $n = $errTask.Result
                if ($n -gt 0) {
                    [void]$sbErr.Append($errBuf, 0, $n)
                    $errTask = $errReader.ReadAsync($errBuf, 0, $errBuf.Length)
                } else {
                    $errTask = $null
                }
            }
            if ($null -ne $outTask -and $outTask.IsCompleted) {
                $n = $outTask.Result
                if ($n -gt 0) {
                    [void]$sbOut.Append($outBuf, 0, $n)
                    $outTask = $outReader.ReadAsync($outBuf, 0, $outBuf.Length)
                } else {
                    $outTask = $null
                }
            }

            # Primary signal source: the debug log file that ghostty writes to
            # after SetStdHandle redirects stderr. Use FileShare.ReadWrite so we
            # don't collide with ghostty's write handle.
            $debugContent = ""
            if (Test-Path $debugLog) {
                try {
                    $fs = [System.IO.File]::Open(
                        $debugLog,
                        [System.IO.FileMode]::Open,
                        [System.IO.FileAccess]::Read,
                        [System.IO.FileShare]::ReadWrite)
                    $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
                    $debugContent = $sr.ReadToEnd()
                    $sr.Close(); $fs.Close()
                } catch {
                    # transient sharing violation -- try next tick
                }
            }

            $combined = $sbErr.ToString() + "`n" + $debugContent

            # Hard-FAIL signals (always precedence over PASS):
            #   - error.InvalidUtf8 literal in log (the canonical bug signature,
            #     usually emitted as "warning(io_thread): error in io thread
            #     err=error.InvalidUtf8")
            #   - "abnormal process exit detected" surface warning (the
            #     subcommand started, then IO thread died mid-read -- the
            #     post-spawn manifestation of the SHELL-env bug)
            if ($combined -match "InvalidUtf8") {
                $verdict = "FAIL"
                $reason  = "InvalidUtf8 observed in log"
                break
            }
            if ($combined -match "abnormal process exit detected") {
                $verdict = "FAIL"
                $reason  = "abnormal process exit (subcommand died, likely IO-thread InvalidUtf8)"
                break
            }

            # Immediate-PASS signal: shell integration was injected (only for
            # bash/zsh/fish -- Windows cmd.exe never emits this line).
            if ($combined -match "shell integration automatically injected") {
                $verdict = "PASS"
                $reason  = "shell integration injected (no abnormal exit)"
                break
            }

            # Grace-window PASS: "started subcommand" appeared, and we've
            # observed the child for long enough without any FAIL signal.
            # Needed for Windows cmd.exe which has no integration line.
            if ($combined -match "started subcommand") {
                if ($null -eq $subcmdSeenAt) {
                    $subcmdSeenAt = [System.Diagnostics.Stopwatch]::StartNew()
                } elseif ($subcmdSeenAt.ElapsedMilliseconds -ge $postSpawnGraceMs) {
                    $verdict = "PASS"
                    $reason  = "subcommand stable for ${postSpawnGraceMs}ms, no Invalid/abnormal"
                    break
                }
            }

            if ($proc.HasExited) {
                $reason = "process exited prematurely (code=$($proc.ExitCode))"
                break
            }
            Start-Sleep -Milliseconds 200
        }
    } catch {
        Write-Host "[$Label] poll loop threw: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Final sweep of debug log (file may have flushed after loop tick).
    $finalDebug = ""
    if (Test-Path $debugLog) {
        try {
            $fs = [System.IO.File]::Open(
                $debugLog,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite)
            $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
            $finalDebug = $sr.ReadToEnd()
            $sr.Close(); $fs.Close()
        } catch {}
    }
    if ($verdict -eq "UNKNOWN") {
        $combined = $sbErr.ToString() + "`n" + $finalDebug
        if ($combined -match "InvalidUtf8") {
            $verdict = "FAIL"; $reason = "InvalidUtf8 on final sweep"
        } elseif ($combined -match "abnormal process exit detected") {
            $verdict = "FAIL"; $reason = "abnormal process exit on final sweep"
        } elseif ($combined -match "shell integration automatically injected") {
            $verdict = "PASS"; $reason = "shell integration injected on final sweep"
        } elseif ($combined -match "started subcommand") {
            # No FAIL signal after timeout, and the subcommand spawned. Treat
            # as PASS -- Windows cmd.exe never emits the integration line.
            $verdict = "PASS"
            $reason  = "subcommand started, no FAIL signal within $TimeoutSec s"
        } else {
            $verdict = "FAIL"
            $reason  = "no subcommand spawn signal within $TimeoutSec s"
        }
    }

    # Bonus: window title probe
    $windowTitle = $null
    try {
        $windowTitle = Find-WindowTitleForPid -TargetPid $procPid
        if ($windowTitle) {
            Write-Host "[$Label] window title: '$windowTitle'" -ForegroundColor DarkCyan
        } else {
            Write-Host "[$Label] no visible top-level window for pid=$procPid" -ForegroundColor DarkYellow
        }
    } catch {
        Write-Host "[$Label] window probe failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    # Kill only our pid
    if (-not $proc.HasExited) {
        try { Stop-Process -Id $procPid -Force -ErrorAction SilentlyContinue } catch {}
        $proc.WaitForExit(2000) | Out-Null
    }
    if (-not $proc.HasExited) {
        Write-Host "[$Label] pid=$procPid would not die; taskkill /T /F" -ForegroundColor Red
        & taskkill /PID $procPid /T /F 2>&1 | Out-Null
    }

    # Drain any final bytes (best-effort)
    try {
        if ($errTask -and $errTask.IsCompleted) {
            $n = $errTask.Result
            if ($n -gt 0) { [void]$sbErr.Append($errBuf, 0, $n) }
        }
        if ($outTask -and $outTask.IsCompleted) {
            $n = $outTask.Result
            if ($n -gt 0) { [void]$sbOut.Append($outBuf, 0, $n) }
        }
    } catch {}

    $sbErr.ToString() | Out-File -FilePath $stderrLog -Encoding utf8
    $sbOut.ToString() | Out-File -FilePath $stdoutLog -Encoding utf8

    # Archive the redirected debug log alongside per-test artifacts.
    $archivedDebugLog = $stderrLog -replace "\.stderr\.log$", ".debug.log"
    if ($finalDebug) {
        $finalDebug | Out-File -FilePath $archivedDebugLog -Encoding utf8
    }

    $color = if ($verdict -eq "PASS") { "Green" } else { "Red" }
    Write-Host "[$Label] VERDICT=$verdict -- $reason" -ForegroundColor $color
    Write-Host "[$Label] stderr log:  $stderrLog"
    if ($finalDebug) { Write-Host "[$Label] debug log:   $archivedDebugLog" }

    return [PSCustomObject]@{
        Label       = $Label
        Verdict     = $verdict
        Reason      = $reason
        StderrLog   = $stderrLog
        DebugLog    = $archivedDebugLog
        WindowTitle = $windowTitle
        Pid         = $procPid
    }
}

# --- Run the two tests ---
$results = @()
$results += Invoke-GhosttyTest -Label "shell-set-bash" -ExtraEnv @{ "SHELL" = "/bin/bash.exe" } -RemoveEnv @()

# Give Windows time to release the debug log file handle from the first test.
Start-Sleep -Milliseconds 1500

$results += Invoke-GhosttyTest -Label "shell-unset-control" -ExtraEnv @{} -RemoveEnv @("SHELL")

# --- Final aggregation ---
Write-Host ""
Write-Host "=== repro-invalidutf8 summary (Mode=$Mode, ExpectFail=$ExpectFail) ===" -ForegroundColor Cyan
foreach ($r in $results) {
    Write-Host ("  {0,-22} -> {1,-4}  ({2})" -f $r.Label, $r.Verdict, $r.Reason)
}

$bug = $results | Where-Object { $_.Label -eq "shell-set-bash" } | Select-Object -First 1
$ctl = $results | Where-Object { $_.Label -eq "shell-unset-control" } | Select-Object -First 1

if (-not $ctl -or $ctl.Verdict -ne "PASS") {
    $ctlVerdict = if ($ctl) { $ctl.Verdict } else { "MISSING" }
    Write-Host "[harness] CONTROL did not PASS (got=$ctlVerdict) -- harness integrity broken" -ForegroundColor Red
    exit 1
}

$expectBug = switch ($Mode) {
    "repro"      { "FAIL" }
    "regression" { "PASS" }
}
if ($ExpectFail) { $expectBug = "FAIL" }

if ($bug.Verdict -eq $expectBug) {
    Write-Host "[harness] bug test matched expectation ($expectBug)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "[harness] bug test MISMATCH -- expected=$expectBug got=$($bug.Verdict)" -ForegroundColor Red
    exit 1
}
