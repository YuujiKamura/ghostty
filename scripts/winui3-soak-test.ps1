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

$exe = if ([System.IO.Path]::IsPathRooted($ExePath)) { $ExePath } else { Join-Path $repoRoot $ExePath }
if (-not (Test-Path $exe)) { Write-Error "ghostty.exe not found at $exe"; return }

# --- Clear old log ---
if (Test-Path $debugLog) {
    Copy-Item $debugLog (Join-Path $outDir "pre_soak_debug.log") -Force
    Remove-Item $debugLog -Force
}

# --- Launch ---
Write-Host "[soak] Launching ghostty (soak $Duration sec)..." -ForegroundColor Cyan
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
Write-Host "  Time(s)  WS(MB)  Handles  Threads | pages  pins  page_size(KB)" -ForegroundColor Gray
Write-Host "  -------  ------  -------  ------- | -----  ----  ------------" -ForegroundColor Gray

$lastDiagLine = 0  # track how far we've read in debug log

function Get-LatestDiagnostic {
    # Parse the most recent DIAGNOSTIC block from ghostty_debug.log
    param([string]$LogPath, [ref]$LastLine)
    $result = @{ pages = "?"; pins = "?"; page_size = "?" }
    if (-not (Test-Path $LogPath)) { return $result }
    try {
        $lines = Get-Content $LogPath -Tail 50 -ErrorAction SilentlyContinue
        if (-not $lines) { return $result }
        # Find last surface[0] line with pages/pins/page_size
        for ($j = $lines.Count - 1; $j -ge 0; $j--) {
            if ($lines[$j] -match 'surface\[0\]\s+pages=(\d+)\s+rows=\d+\s+cols=\d+\s+pins=(\d+)\s+page_size=(\d+)') {
                $result.pages = $Matches[1]
                $result.pins = $Matches[2]
                $result.page_size = [Math]::Round([int]$Matches[3] / 1KB, 1)
                break
            }
        }
    } catch {}
    return $result
}

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

    # Internal state from diagnostic log
    $diag = Get-LatestDiagnostic -LogPath $debugLog -LastLine ([ref]$lastDiagLine)

    $sample = [PSCustomObject]@{
        ElapsedSec = $elapsed
        WorkingSetMB = $ws
        Handles = $handles
        Threads = $threads
        Pages = $diag.pages
        Pins = $diag.pins
        PageSizeKB = $diag.page_size
    }
    $samples += $sample

    Write-Host ("  {0,7}  {1,6}  {2,7}  {3,7} | {4,5}  {5,4}  {6,12}" -f $elapsed, $ws, $handles, $threads, $diag.pages, $diag.pins, $diag.page_size)

    # Detect memory explosion (>1GB working set)
    if ($ws -gt 1024) {
        Write-Host "[soak] WARNING: Working set > 1GB ($ws MB)" -ForegroundColor Red
    }

    # Detect internal state growth
    if ($samples.Count -ge 2 -and $diag.pages -ne "?") {
        $prevPages = $samples[-2].Pages
        if ($prevPages -ne "?" -and [int]$diag.pages -gt [int]$prevPages + 10) {
            Write-Host "[soak] WARNING: Pages growing rapidly ($prevPages -> $($diag.pages))" -ForegroundColor Yellow
        }
    }

    # Detect hang (log unchanged for 3 consecutive samples)
    $logSize = 0
    if (Test-Path $debugLog) { $logSize = (Get-Item $debugLog).Length }
    if ($samples.Count -ge 3) {
        $last3LogSizes = @($samples[-3].LogSizeKB, $samples[-2].LogSizeKB, $logSize)
        if (($last3LogSizes | Sort-Object -Unique).Count -eq 1) {
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
