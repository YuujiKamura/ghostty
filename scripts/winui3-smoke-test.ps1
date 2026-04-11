#!/usr/bin/env pwsh
# WinUI3 Smoke Test — verify ghostty.exe starts and reaches init_complete.
# Usage: ./scripts/winui3-smoke-test.ps1 [-ExePath zig-out-winui3/bin/ghostty.exe] [-TimeoutSec 30]
param(
    [string]$ExePath = "zig-out-winui3/bin/ghostty.exe",
    [int]$TimeoutSec = 30
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ExePath)) {
    Write-Error "SMOKE FAIL: $ExePath not found"
    exit 1
}

$debugLog = Join-Path $env:TEMP "ghostty_debug.log"
if (Test-Path $debugLog) { Remove-Item $debugLog -Force }

Write-Host "[smoke] Starting $ExePath ..."
$proc = Start-Process -FilePath $ExePath -PassThru -WindowStyle Hidden

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$reached = $false
$stages = @()

while ((Get-Date) -lt $deadline) {
    # Check if process died
    if ($proc.HasExited) {
        Write-Host "[smoke] Process exited with code $($proc.ExitCode) before init_complete"
        if (Test-Path $debugLog) {
            Write-Host "[smoke] Debug log tail:"
            Get-Content $debugLog -Tail 20 | ForEach-Object { Write-Host "  $_" }
        }
        Write-Error "SMOKE FAIL: ghostty.exe crashed (exit=$($proc.ExitCode))"
        exit 1
    }

    # Check debug log for progress
    if (Test-Path $debugLog) {
        $content = Get-Content $debugLog -Raw -ErrorAction SilentlyContinue
        if ($content) {
            # Collect stages
            $stageMatches = [regex]::Matches($content, "startup stage: (\w+)")
            $stages = $stageMatches | ForEach-Object { $_.Groups[1].Value }

            if ($content -match "startup stage: init_complete") {
                $reached = $true
                break
            }
            if ($content -match "startup stage: failed") {
                Write-Host "[smoke] Init failed. Stages reached: $($stages -join ' -> ')"
                if ($content -match "error.*?:.*$") {
                    $errors = [regex]::Matches($content, "error\(winui3\):.*")
                    $errors | ForEach-Object { Write-Host "  $($_.Value)" }
                }
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                Write-Error "SMOKE FAIL: startup stage: failed"
                exit 1
            }
        }
    }

    Start-Sleep -Milliseconds 500
}

# Clean up
Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue

if ($reached) {
    Write-Host "[smoke] PASS: init_complete reached. Stages: $($stages -join ' -> ')"
    exit 0
} else {
    Write-Host "[smoke] Stages reached: $($stages -join ' -> ')"
    Write-Error "SMOKE FAIL: init_complete not reached within ${TimeoutSec}s"
    exit 1
}
