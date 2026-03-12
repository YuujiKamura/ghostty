<#
.SYNOPSIS
    Soak test: sustained heavy output to detect internal state overflow.
    Targets Page/PageList buffer limits, COM reference leaks, PTY saturation.

.PARAMETER Duration
    Test duration in seconds (default: 120 = 2 minutes)
.PARAMETER NoBuild
    Skip build step
.PARAMETER SampleInterval
    Memory sampling interval in seconds (default: 5)
#>
param(
    [int]$Duration = 120,
    [switch]$NoBuild,
    [int]$SampleInterval = 5,
    [string]$ExePath = "zig-out-winui3\bin\ghostty.exe",
    [ValidateSet("steady","targeted")][string]$Load = "targeted"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$debugLog = "$env:USERPROFILE\ghostty_debug.log"
$outDir = Join-Path $repoRoot "tmp\soak-test"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

# --- Build ---
if (-not $NoBuild) {
    Write-Host "[soak] Building WinUI3..." -ForegroundColor Cyan
    Push-Location $repoRoot
    bash -c "./build-winui3.sh" 2>&1 | Select-Object -Last 3
    Pop-Location
}

$exe = Join-Path $repoRoot $ExePath
if (-not (Test-Path $exe)) { Write-Error "ghostty.exe not found at $exe"; return }

# --- Clear old log ---
if (Test-Path $debugLog) {
    Copy-Item $debugLog (Join-Path $outDir "pre_soak_debug.log") -Force
    Remove-Item $debugLog -Force
}

# --- Launch ---
Write-Host "[soak] Launching ghostty (soak $Duration sec)..." -ForegroundColor Cyan
$env:GHOSTTY_WINUI3_ENABLE_TABVIEW = "1"
$env:GHOSTTY_WINUI3_ENABLE_TABVIEW_HANDLERS = "1"
$proc = Start-Process -FilePath $exe -PassThru

# Wait for window
$maxWait = 20
for ($i = 0; $i -lt $maxWait; $i++) {
    Start-Sleep -Seconds 1
    if ($proc.HasExited) { Write-Error "[soak] ghostty exited early (exit=$($proc.ExitCode))"; return }
    $proc = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
    if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) { break }
}
$hwnd = $proc.MainWindowHandle
if ($hwnd -eq [IntPtr]::Zero) { Write-Error "[soak] No window after ${maxWait}s"; return }
Write-Host "[soak] Window: 0x$($hwnd.ToString('X'))" -ForegroundColor Green

# --- Inject steady_load command via WM_CHAR ---
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Soak {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
}
"@

Start-Sleep -Seconds 2
$scriptName = if ($Load -eq "targeted") { "targeted_load.py" } else { "steady_load.py" }
$loadCmd = "python $($repoRoot -replace '\\','/')/scripts/$scriptName $Duration"
foreach ($ch in $loadCmd.ToCharArray()) {
    [Win32Soak]::PostMessage($hwnd, 0x0102, [IntPtr]::new([int]$ch), [IntPtr]::Zero) | Out-Null
}
[Win32Soak]::PostMessage($hwnd, 0x0102, [IntPtr]::new(0x0D), [IntPtr]::Zero) | Out-Null
Write-Host "[soak] Injected: $loadCmd" -ForegroundColor Green

# --- Monitor loop ---
$startTime = [DateTime]::UtcNow
$samples = @()
$crashDetected = $false
$hangDetected = $false
$prevLogSize = 0

Write-Host "[soak] Monitoring for $Duration sec (sample every ${SampleInterval}s)..." -ForegroundColor Yellow
Write-Host ""
Write-Host "  Time(s)  WorkingSet(MB)  Handles  Threads  LogSize(KB)" -ForegroundColor Gray
Write-Host "  -------  --------------  -------  -------  -----------" -ForegroundColor Gray

while (([DateTime]::UtcNow - $startTime).TotalSeconds -lt ($Duration + 10)) {
    Start-Sleep -Seconds $SampleInterval

    if ($proc.HasExited) {
        $crashDetected = $true
        Write-Host "[soak] CRASH at $([int]([DateTime]::UtcNow - $startTime).TotalSeconds)s (exit=$($proc.ExitCode))" -ForegroundColor Red
        break
    }

    # Refresh process metrics
    $proc = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
    if (-not $proc) { $crashDetected = $true; break }

    $ws = [Math]::Round($proc.WorkingSet64 / 1MB, 1)
    $handles = $proc.HandleCount
    $threads = $proc.Threads.Count
    $elapsed = [int]([DateTime]::UtcNow - $startTime).TotalSeconds

    # Check log growth (proxy for "still processing output")
    $logSize = 0
    if (Test-Path $debugLog) { $logSize = (Get-Item $debugLog).Length }
    $logKB = [Math]::Round($logSize / 1KB, 1)

    $sample = [PSCustomObject]@{
        ElapsedSec = $elapsed
        WorkingSetMB = $ws
        Handles = $handles
        Threads = $threads
        LogSizeKB = $logKB
    }
    $samples += $sample

    Write-Host ("  {0,7}  {1,14}  {2,7}  {3,7}  {4,11}" -f $elapsed, $ws, $handles, $threads, $logKB)

    # Detect memory explosion (>1GB working set)
    if ($ws -gt 1024) {
        Write-Host "[soak] WARNING: Working set > 1GB ($ws MB)" -ForegroundColor Red
    }

    # Detect hang (log size unchanged for 3 consecutive samples)
    if ($samples.Count -ge 3) {
        $last3 = $samples[-3..-1]
        if (($last3 | ForEach-Object { $_.LogSizeKB } | Sort-Object -Unique).Count -eq 1) {
            # Log hasn't changed but process is alive — possible hang
            # Only flag if we're in the middle of the test (not at the end)
            if ($elapsed -lt ($Duration - 20)) {
                $hangDetected = $true
                Write-Host "[soak] WARNING: Possible hang (log unchanged for 3 samples)" -ForegroundColor Yellow
            }
        }
    }

    $prevLogSize = $logSize
}

# --- Results ---
Write-Host ""
Write-Host "=== Soak Test Results ===" -ForegroundColor Cyan
Write-Host "  Duration:    $([int]([DateTime]::UtcNow - $startTime).TotalSeconds) sec"
Write-Host "  Samples:     $($samples.Count)"

if ($samples.Count -gt 0) {
    $peakMem = ($samples | Measure-Object -Property WorkingSetMB -Maximum).Maximum
    $peakHandles = ($samples | Measure-Object -Property Handles -Maximum).Maximum
    $startMem = $samples[0].WorkingSetMB
    $endMem = $samples[-1].WorkingSetMB
    $memGrowth = [Math]::Round($endMem - $startMem, 1)

    Write-Host "  Memory:      $startMem -> $endMem MB (peak: $peakMem MB, growth: ${memGrowth} MB)"
    Write-Host "  Peak handles: $peakHandles"
}

if ($crashDetected) {
    Write-Host "  Result:      CRASH (exit=$($proc.ExitCode))" -ForegroundColor Red
} elseif ($hangDetected) {
    Write-Host "  Result:      HANG DETECTED" -ForegroundColor Yellow
} else {
    Write-Host "  Result:      SURVIVED" -ForegroundColor Green
}

# Graceful shutdown
if (-not $proc.HasExited) {
    $proc.CloseMainWindow() | Out-Null
    $proc.WaitForExit(5000) | Out-Null
    if (-not $proc.HasExited) { $proc.Kill() }
}

# --- Save ---
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
if (Test-Path $debugLog) {
    Copy-Item $debugLog (Join-Path $outDir "soak_${timestamp}.log")
}
$samples | Export-Csv (Join-Path $outDir "soak_${timestamp}_metrics.csv") -NoTypeInformation
Write-Host "  Metrics:     $outDir\soak_${timestamp}_metrics.csv" -ForegroundColor Gray

if (Test-Path $debugLog) {
    $vehLines = Select-String -Path $debugLog -Pattern "VEH Exception|UNHANDLED EXCEPTION|skipping focus"
    if ($vehLines) {
        Write-Host "  VEH/Guard:" -ForegroundColor Yellow
        $vehLines | ForEach-Object { Write-Host "    $($_.Line)" }
    }
}
Write-Host ""
