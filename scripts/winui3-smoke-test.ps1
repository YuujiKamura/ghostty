#!/usr/bin/env pwsh
# WinUI3 Smoke Test — verify ghostty.exe starts and initializes correctly.
#
# Desktop mode (default): requires init_complete (full XAML window).
# Headless mode (-Headless): accepts App.init EXIT OK (no desktop needed).
#   Use -Headless on CI runners that lack a GUI session.
#
# Usage:
#   ./scripts/winui3-smoke-test.ps1                          # desktop
#   ./scripts/winui3-smoke-test.ps1 -Headless -TimeoutSec 15 # CI
param(
    [string]$ExePath = "zig-out-winui3/bin/ghostty.exe",
    [int]$TimeoutSec = 30,
    [switch]$Headless
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ExePath)) {
    Write-Error "SMOKE FAIL: $ExePath not found"
    exit 1
}

$passPattern = if ($Headless) { "App\.init: EXIT OK" } else { "startup stage: init_complete" }
$passLabel   = if ($Headless) { "App.init EXIT OK (headless)" } else { "init_complete" }

Write-Host "[smoke] Mode: $(if ($Headless) {'headless (CI)'} else {'desktop'})"
Write-Host "[smoke] Pass condition: $passLabel"
Write-Host "[smoke] Starting $ExePath ..."
$proc = Start-Process -FilePath $ExePath -PassThru -WindowStyle Hidden

# Per-PID log path. attachDebugConsole() writes to %TEMP%\ghostty_debug_<pid>.log
# (see Get-GhosttyLogPath in tests/winui3/test-helpers.psm1 for the canonical
# resolver). Fresh per launch — no pre-clear step needed.
$debugLog = Join-Path $env:TEMP "ghostty_debug_$($proc.Id).log"

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$reached = $false
$stages = @()
$lastContent = ""

while ((Get-Date) -lt $deadline) {
    if (Test-Path $debugLog) {
        $content = Get-Content $debugLog -Raw -ErrorAction SilentlyContinue
        if ($content) {
            $lastContent = $content
            $stageMatches = [regex]::Matches($content, "startup stage: (\w+)")
            $stages = $stageMatches | ForEach-Object { $_.Groups[1].Value }

            if ($content -match $passPattern) {
                $reached = $true
                break
            }
            if ($content -match "startup stage: failed") {
                Write-Host "[smoke] Init failed. Stages reached: $($stages -join ' -> ')"
                $errors = [regex]::Matches($content, "error\(winui3\):.*")
                $errors | ForEach-Object { Write-Host "  $($_.Value)" }
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                Write-Error "SMOKE FAIL: startup stage: failed"
                exit 1
            }
        }
    }

    # Process died — check if it already passed before crashing
    if ($proc.HasExited) {
        # Re-read log one final time
        if (Test-Path $debugLog) {
            $lastContent = Get-Content $debugLog -Raw -ErrorAction SilentlyContinue
            if ($lastContent -match $passPattern) {
                $reached = $true
                break
            }
        }
        Write-Host "[smoke] Process exited with code $($proc.ExitCode)"
        if ($lastContent) {
            Write-Host "[smoke] Debug log tail:"
            Get-Content $debugLog -Tail 15 | ForEach-Object { Write-Host "  $_" }
        }
        Write-Error "SMOKE FAIL: ghostty.exe crashed (exit=$($proc.ExitCode)) before $passLabel"
        exit 1
    }

    Start-Sleep -Milliseconds 500
}

# Clean up
Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue

if ($reached) {
    Write-Host "[smoke] PASS: $passLabel reached. Stages: $($stages -join ' -> ')"
    exit 0
} else {
    Write-Host "[smoke] Stages reached: $($stages -join ' -> ')"
    Write-Error "SMOKE FAIL: $passLabel not reached within ${TimeoutSec}s"
    exit 1
}
