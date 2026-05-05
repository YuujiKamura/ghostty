# test-cp-session-file-appears.ps1 — core-smoke
#
# Single-responsibility test: when ghostty.exe boots, does the .session file
# appear in %LOCALAPPDATA%\ghostty\control-plane\winui3\sessions\ before the
# process exits? Schema-validate the contents.
#
# This is the smallest in-vivo assertion that pins the integration contract
# the existing SessionManager unit tests cannot cover (those run inside the
# test runner process, not via a real ghostty.exe boot).
#
# Exit codes:
#   0  — file appeared, schema OK
#   1  — ghostty.exe missing
#   2  — ghostty exited before file appeared
#   3  — timeout, no .session file for our PID
#   4  — file appeared but schema check failed
#
# Usage:
#   pwsh -NoProfile -File tests\winui3\test-cp-session-file-appears.ps1

param(
    [string]$ExePath = (Join-Path $PSScriptRoot '..\..\zig-out-winui3\bin\ghostty.exe'),
    [int]$TimeoutSec = 8
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not (Test-Path $ExePath)) {
    Write-Host "ERROR: ghostty.exe not found at $ExePath" -ForegroundColor Red
    exit 1
}

$sessionsDir = Join-Path $env:LOCALAPPDATA 'ghostty\control-plane\winui3\sessions'

# Pre-clean so we measure THIS launch, not leftover from previous runs.
if (Test-Path $sessionsDir) {
    Get-ChildItem $sessionsDir -Filter '*.session' -Force -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

Write-Host "Launching: $ExePath" -ForegroundColor Cyan
$proc = Start-Process -FilePath $ExePath -PassThru -WindowStyle Minimized
$ghostPid = $proc.Id
Write-Host "PID: $ghostPid" -ForegroundColor Cyan
Write-Host "Watching: $sessionsDir" -ForegroundColor Cyan

$found = $null
try {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ($proc.HasExited) {
            Write-Host "FAIL: ghostty exited before session file appeared (exit code $($proc.ExitCode))" -ForegroundColor Red
            exit 2
        }
        if (Test-Path $sessionsDir) {
            $matched = Get-ChildItem $sessionsDir -Filter "*-$ghostPid.session" -Force -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($matched) {
                $found = $matched
                break
            }
        }
        Start-Sleep -Milliseconds 100
    }

    if (-not $found) {
        Write-Host "FAIL: no *-$ghostPid.session in $sessionsDir within ${TimeoutSec}s" -ForegroundColor Red
        if (Test-Path $sessionsDir) {
            Write-Host "  dir listing:" -ForegroundColor Yellow
            $entries = @(Get-ChildItem $sessionsDir -Force -ErrorAction SilentlyContinue)
            if ($entries.Count -eq 0) {
                Write-Host "    (empty)" -ForegroundColor Yellow
            } else {
                $entries | Format-Table Name, Length, LastWriteTime -AutoSize | Out-String | Write-Host
            }
        } else {
            Write-Host "  dir does NOT exist: $sessionsDir" -ForegroundColor Yellow
        }
        # Also probe sibling dirs deckpilot may scan, in case writeFile is
        # going somewhere unexpected.
        $altDirs = @(
            (Join-Path $env:LOCALAPPDATA 'WindowsTerminal\control-plane\winui3\sessions'),
            (Join-Path $env:LOCALAPPDATA 'ghostty\control-plane\win32\sessions'),
            (Join-Path $env:LOCALAPPDATA 'ghostty\control-plane\web\sessions')
        )
        foreach ($a in $altDirs) {
            if (Test-Path $a) {
                $alt = @(Get-ChildItem $a -Filter "*-$ghostPid.session" -Force -ErrorAction SilentlyContinue)
                if ($alt.Count -gt 0) {
                    Write-Host "  HINT: file IS at unexpected path: $($alt[0].FullName)" -ForegroundColor Magenta
                }
            }
        }
        exit 3
    }

    Write-Host "PASS: file appeared: $($found.FullName)" -ForegroundColor Green
    $age_ms = ((Get-Date) - $found.CreationTime).TotalMilliseconds
    Write-Host "  appeared after ~${age_ms}ms"

    Write-Host "--- contents ---"
    $contents = Get-Content $found.FullName -Raw
    Write-Output $contents
    Write-Host "--- /contents ---"

    $required = @("pid=$ghostPid", "pipe_path=", "session_name=")
    $missing = @()
    foreach ($key in $required) {
        if ($contents -notmatch [regex]::Escape($key)) { $missing += $key }
    }
    if ($missing.Count -gt 0) {
        Write-Host "FAIL: missing required keys: $($missing -join ', ')" -ForegroundColor Red
        exit 4
    }
    Write-Host "PASS: all required keys present (pid, pipe_path, session_name)" -ForegroundColor Green

    # ── Cross-tool observation: does deckpilot.exe (the binary the test
    #    driver actually uses) discover this session via file scan + Ping? ──
    $deckpilot = Join-Path $PSScriptRoot '..\..\zig-out-winui3\bin\deckpilot.exe'
    if (-not (Test-Path $deckpilot)) {
        $inPath = Get-Command deckpilot -ErrorAction SilentlyContinue
        if ($inPath) { $deckpilot = $inPath.Source }
    }
    if (Test-Path $deckpilot) {
        Write-Host "--- deckpilot list (binary: $deckpilot) ---"
        $listOut = & $deckpilot list 2>&1
        $listExit = $LASTEXITCODE
        Write-Host "exit=$listExit"
        $listOut | ForEach-Object { Write-Host "  $_" }
        $found = $false
        foreach ($line in $listOut) {
            if ($line -match "$ghostPid") { $found = $true; break }
        }
        if ($found) {
            Write-Host "PASS: deckpilot list contains PID $ghostPid" -ForegroundColor Green
        } else {
            Write-Host "FAIL: deckpilot list does NOT contain PID $ghostPid (file exists but Ping likely failed)" -ForegroundColor Red
            # Probe the pipe directly to localize: is the pipe actually listening?
            $pipePath = "\\.\pipe\ghostty-winui3-ghostty-$ghostPid-$ghostPid"
            Write-Host "--- direct pipe probe: $pipePath ---"
            try {
                $client = [System.IO.File]::Open($pipePath, 'Open', 'Read')
                $client.Close()
                Write-Host "  PIPE IS LISTENING (open succeeded). deckpilot.exe Ping logic differs from raw open." -ForegroundColor Yellow
            } catch {
                Write-Host "  PIPE NOT LISTENING (open failed: $($_.Exception.Message))" -ForegroundColor Yellow
            }
            exit 5
        }
    } else {
        Write-Host "WARN: deckpilot.exe not found, skipping cross-tool check" -ForegroundColor Yellow
    }
    exit 0
}
finally {
    if (-not $proc.HasExited) {
        Stop-Process -Id $ghostPid -Force -ErrorAction SilentlyContinue
    }
}
