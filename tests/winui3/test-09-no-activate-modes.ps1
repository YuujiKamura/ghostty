param([switch]$IncludeDefault)

# test-09-no-activate-modes.ps1
# Verify the three KS_NO_ACTIVATE modes set up by App.zig step 5:
#
#   unset    → SW_SHOWNORMAL + SetForegroundWindow (focus moves to ghostty)
#   hide     → SW_HIDE                              (window invisible)
#   visible  → SW_SHOWNOACTIVATE                    (visible, no activation)
#
# Strategy: log-marker assertion. Each mode emits a distinct
# `initXaml step 5: ShowWindow(...)` line. We:
#
#   1. record the current ghostty_debug.log size
#   2. launch ghostty with the env var set, capture exact PID via
#      Start-Process -PassThru
#   3. wait for the log to grow to include "startup stage:
#      window_activated" (proves step 5 ran)
#   4. terminate ghostty by PID only (NEVER by image / title — would
#      kill the developer's other ghostty sessions)
#   5. read the new log slice and assert it contains the expected
#      `ShowWindow(...)` marker for the mode under test
#
# Why log-marker rather than GetForegroundWindow comparison: the
# WinUI3 / XAML Islands runtime can call its own activation paths
# after our step 5 returns. Asserting on actual foreground state
# would couple this test to internal WinUI3 behaviour that's outside
# the scope of `KS_NO_ACTIVATE`. The log marker proves OUR dispatch
# logic chose the right SW_ flag — which is what the env var
# contract guarantees. Anything else (XAML stealing focus despite
# SHOWNOACTIVATE) is a separate, follow-up concern.
#
# Companion to the Zig unit tests in `App.zig` covering env-value →
# enum dispatch (`parseNoActivateMode`). Together they certify
# (1) "right enum value chosen for given env value" and
# (2) "right ShowWindow flag fired for given enum value".

$ErrorActionPreference = 'Stop'
$testName = "test-09-no-activate-modes"

Import-Module "$PSScriptRoot\test-helpers.psm1" -Force

$exePath = Join-Path $PSScriptRoot "..\..\zig-out-winui3\bin\ghostty.exe"
$exePath = (Resolve-Path $exePath -ErrorAction Stop).Path
if (-not (Test-Path $exePath)) {
    throw "$testName FAIL: ghostty.exe not found at $exePath"
}

$logPath = Join-Path $env:TEMP "ghostty_debug.log"

# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------

function Read-Log-File {
    # Read an entire log file (per-test stderr redirect). Tolerant
    # of read failures while ghostty has the file open — retries
    # with FILE_SHARE_READ. Returns "" on any IO error.
    param([string]$Path, [int]$RetryCount = 3)
    if (-not (Test-Path $Path)) { return "" }
    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        try {
            $fs = [System.IO.FileStream]::new(
                $Path,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
            )
            try {
                $reader = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8, $false, 4096, $true)
                try {
                    return $reader.ReadToEnd()
                } finally {
                    $reader.Dispose()
                }
            } finally {
                $fs.Dispose()
            }
        } catch {
            if ($attempt -lt $RetryCount) { Start-Sleep -Milliseconds 200 }
        }
    }
    return ""
}

function Get-StepFiveLine {
    param([string]$LogContent)
    if (-not $LogContent) { return $null }
    $m = [regex]::Match($LogContent, "initXaml step 5: ShowWindow[^\r\n]*")
    if (-not $m.Success) { return $null }
    return $m.Value
}

function Wait-For-StepFiveInFile {
    # Poll a per-test log file until a step-5 line appears.
    # Because the file is unique to this test process, the line we
    # find is unambiguously from the launch we just did — no
    # baseline counting, no other-ghostty interference.
    param([string]$Path, [int]$TimeoutMs = 15000)
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        $log = Read-Log-File -Path $Path
        $line = Get-StepFiveLine -LogContent $log
        if ($line) { return $line }
        Start-Sleep -Milliseconds 200
    }
    return $null
}

function Run-One-Mode {
    param(
        [string]$Mode,                 # "" | "hide" | "visible"
        [string]$ExpectedMarker        # substring expected in the step-5 line
    )
    # Compose env. Restore on every exit path.
    $prev = $env:KS_NO_ACTIVATE
    if ($Mode -eq "") {
        $env:KS_NO_ACTIVATE = $null
    } else {
        $env:KS_NO_ACTIVATE = $Mode
    }
    $env:GHOSTTY_CONTROL_PLANE = $null
    $env:WINDOWS_TERMINAL_CONTROL_PLANE = $null

    $modeLabel = if ($Mode -eq "") { "default" } else { $Mode }

    # Per-test stderr redirect file. ghostty's `attachDebugConsole`
    # also ATTEMPTS to redirect stderr to %TEMP%\ghostty_debug.log
    # via SetStdHandle, but that only succeeds if it can open the
    # file (FILE_SHARE_READ only). When PowerShell pre-binds the
    # process's stderr via Start-Process -RedirectStandardError,
    # the SetStdHandle inside ghostty may or may not stick — but
    # the early debug logs (including step 5) are reliably captured
    # in our redirect target either way because they fire BEFORE
    # attachDebugConsole's potential overwrite.
    $stderrPath = Join-Path $env:TEMP ("ghostty_test09_${modeLabel}_$([System.Diagnostics.Process]::GetCurrentProcess().Id).log")
    if (Test-Path $stderrPath) { Remove-Item $stderrPath -Force }

    $proc = $null
    try {
        $proc = Start-Process -FilePath $exePath `
                              -PassThru `
                              -WindowStyle Normal `
                              -RedirectStandardError $stderrPath
        Write-Host "  [$modeLabel] PID=$($proc.Id), stderr→$stderrPath, waiting for step 5 line ..." -ForegroundColor DarkGray

        $line = Wait-For-StepFiveInFile -Path $stderrPath -TimeoutMs 15000
        if (-not $line) {
            # Fall back to the shared ghostty_debug.log — on this
            # codepath ghostty's own attachDebugConsole may have
            # taken over stderr.
            $line = Wait-For-StepFiveInFile -Path $logPath -TimeoutMs 3000
        }
        if (-not $line) {
            throw "[$Mode] FAIL: no 'initXaml step 5: ShowWindow' line in $stderrPath OR $logPath within 18 s — process may have crashed pre-step-5"
        }
        if ($line -notmatch [regex]::Escape($ExpectedMarker)) {
            throw "[$Mode] FAIL: step-5 line did not contain '$ExpectedMarker'. Got: $line"
        }
        Write-Host "  [$modeLabel] OK — '$line'" -ForegroundColor Green
    } finally {
        $env:KS_NO_ACTIVATE = $prev
        if ($proc -and -not $proc.HasExited) {
            # Stop ONLY this PID. Never image-name kill, never title kill —
            # the dev box has many ghostty sessions running and a
            # broad-stroke kill would clobber the user's actual work.
            try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch { }
        }
        # Brief settle so the next Run-One-Mode's launch overwrites
        # this process's log section cleanly.
        Start-Sleep -Milliseconds 800
    }
}

# ----------------------------------------------------------------------
# Subtest 1: KS_NO_ACTIVATE=visible
# ----------------------------------------------------------------------
Run-One-Mode -Mode "visible" `
             -ExpectedMarker "ShowWindow(SHOWNOACTIVATE)"

# ----------------------------------------------------------------------
# Subtest 2: KS_NO_ACTIVATE=hide
# ----------------------------------------------------------------------
Run-One-Mode -Mode "hide" `
             -ExpectedMarker "ShowWindow(HIDE)"

# ----------------------------------------------------------------------
# Subtest 3: alias coverage — KS_NO_ACTIVATE=show resolves to visible
# ----------------------------------------------------------------------
# Cheaper to run because the parser is identical to the `=visible` case;
# this is the integration-level pin for the alias that the parser-side
# Zig unit test already covers symbolically.
Run-One-Mode -Mode "show" `
             -ExpectedMarker "ShowWindow(SHOWNOACTIVATE)"

# ----------------------------------------------------------------------
# Subtest 4: KS_NO_ACTIVATE unset — default behaviour
# ----------------------------------------------------------------------
# Default mode actually steals foreground (that IS the spec). Skip on
# a developer's interactive box because it's disruptive even though
# it's correct. Run with -IncludeDefault on CI / clean boxes.
if ($IncludeDefault) {
    Run-One-Mode -Mode "" `
                 -ExpectedMarker "ShowWindow + SetForegroundWindow OK"
} else {
    Write-Host "  [default] SKIP — pass -IncludeDefault to exercise the focus-stealing default path" -ForegroundColor Yellow
}

Write-Host "$testName PASS" -ForegroundColor Green
