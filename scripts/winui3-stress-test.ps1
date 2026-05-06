<#
.SYNOPSIS
    Stress test for ghostty WinUI3: heavy output + window operations.
    Tests maximize/restore/resize under load to detect crashes and state corruption.
    Does NOT grab mouse cursor or foreground — safe to run while working.

.PARAMETER Duration
    Total test duration in seconds (default: 30)
.PARAMETER NoBuild
    Skip build step
.PARAMETER ExePath
    Path to ghostty.exe (default: zig-out-winui3/bin/ghostty.exe)
#>
param(
    [int]$Duration = 30,
    [switch]$NoBuild,
    [string]$ExePath = "zig-out-winui3\bin\ghostty.exe"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $repoRoot "tmp\stress-test"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
# $debugLog is set after Start-Process below — it's a per-PID file under
# %TEMP% (attachDebugConsole writes to %TEMP%\ghostty_debug_<pid>.log).

# --- Win32 API (no SendInput / no cursor manipulation) ---
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Stress {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    public const int SW_MAXIMIZE = 3;
    public const int SW_RESTORE = 9;
    public const int SW_MINIMIZE = 6;

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    public static IntPtr MakeLParam(int lo, int hi) {
        return (IntPtr)((hi << 16) | (lo & 0xFFFF));
    }
}
"@

# --- Build ---
if (-not $NoBuild) {
    Write-Host "[stress] Building WinUI3..." -ForegroundColor Cyan
    Push-Location $repoRoot
    bash -c "./build-winui3.sh" 2>&1 | Select-Object -Last 3
    Pop-Location
}

$exe = if ([System.IO.Path]::IsPathRooted($ExePath)) { $ExePath } else { Join-Path $repoRoot $ExePath }
if (-not (Test-Path $exe)) {
    Write-Error "ghostty.exe not found at $exe"
    return
}

# --- Launch ghostty ---
Write-Host "[stress] Launching ghostty ($Duration sec)..." -ForegroundColor Cyan
$proc = Start-Process -FilePath $exe -PassThru

# Per-PID log path. Pre-2026-05-06 this script targeted
# %USERPROFILE%\ghostty_debug.log which the binary never produced. The
# real path is %TEMP%\ghostty_debug_<pid>.log written by
# attachDebugConsole(). Fresh per-launch, no pre-clear step needed.
$debugLog = Join-Path $env:TEMP "ghostty_debug_$($proc.Id).log"

# Wait for window to appear
$hwnd = [IntPtr]::Zero
$maxWait = 20
for ($i = 0; $i -lt $maxWait; $i++) {
    Start-Sleep -Seconds 1
    if ($proc.HasExited) {
        Write-Error "[stress] ghostty exited before window appeared (exit=$($proc.ExitCode))"
        return
    }
    $proc = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
    if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) {
        $hwnd = $proc.MainWindowHandle
        break
    }
}
if ($hwnd -eq [IntPtr]::Zero) {
    Write-Warning "[stress] MainWindowHandle not found, trying FindWindow..."
    foreach ($title in @("ghostty", "Ghostty", "")) {
        $hwnd = [Win32Stress]::FindWindow($null, $title)
        if ($hwnd -ne [IntPtr]::Zero) { break }
    }
}
if ($hwnd -eq [IntPtr]::Zero) {
    Write-Error "[stress] No window found after ${maxWait}s"
    return
}
Write-Host "[stress] Window: 0x$($hwnd.ToString('X'))" -ForegroundColor Green

# Inject output load via WM_CHAR (no cursor grab)
Start-Sleep -Seconds 2
$loadCmd = "python $($repoRoot -replace '\\','/')/scripts/steady_load.py $Duration"
foreach ($ch in $loadCmd.ToCharArray()) {
    [Win32Stress]::PostMessage($hwnd, 0x0102, [IntPtr]::new([int]$ch), [IntPtr]::Zero) | Out-Null
}
[Win32Stress]::PostMessage($hwnd, 0x0102, [IntPtr]::new(0x0D), [IntPtr]::Zero) | Out-Null
Write-Host "[stress] Injected load command" -ForegroundColor Green
Start-Sleep -Seconds 2

# --- Stress loop: window operations only (no mouse grab) ---
$rng = [System.Random]::new()
$startTime = [DateTime]::UtcNow
$opCount = 0
$crashDetected = $false

Write-Host "[stress] Running window operations for $Duration seconds..." -ForegroundColor Yellow

while (([DateTime]::UtcNow - $startTime).TotalSeconds -lt $Duration) {
    if ($proc.HasExited) {
        $crashDetected = $true
        Write-Host "[stress] CRASH at op #$opCount (exit=$($proc.ExitCode))" -ForegroundColor Red
        break
    }

    $op = $rng.Next(4)
    switch ($op) {
        0 { # Maximize
            [Win32Stress]::ShowWindow($hwnd, [Win32Stress]::SW_MAXIMIZE) | Out-Null
        }
        1 { # Restore
            [Win32Stress]::ShowWindow($hwnd, [Win32Stress]::SW_RESTORE) | Out-Null
        }
        2 { # Random resize
            $rect = New-Object Win32Stress+RECT
            [Win32Stress]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
            $w = ($rect.Right - $rect.Left) + $rng.Next(-50, 50)
            $h = ($rect.Bottom - $rect.Top) + $rng.Next(-50, 50)
            $w = [Math]::Max(400, [Math]::Min(2000, $w))
            $h = [Math]::Max(300, [Math]::Min(1200, $h))
            [Win32Stress]::MoveWindow($hwnd, $rect.Left, $rect.Top, $w, $h, $true) | Out-Null
        }
        3 { # Rapid maximize-restore (crash trigger pattern)
            [Win32Stress]::ShowWindow($hwnd, [Win32Stress]::SW_MAXIMIZE) | Out-Null
            Start-Sleep -Milliseconds 50
            [Win32Stress]::ShowWindow($hwnd, [Win32Stress]::SW_RESTORE) | Out-Null
        }
    }
    $opCount++
    Start-Sleep -Milliseconds ($rng.Next(30, 200))
}

# --- Results ---
Write-Host ""
Write-Host "=== Stress Test Results ===" -ForegroundColor Cyan
Write-Host "  Operations: $opCount"
Write-Host "  Duration:   $([int]([DateTime]::UtcNow - $startTime).TotalSeconds) sec"

if ($crashDetected) {
    Write-Host "  Result:     CRASH (exit=$($proc.ExitCode))" -ForegroundColor Red
} elseif ($proc.HasExited) {
    Write-Host "  Result:     Exited (exit=$($proc.ExitCode))" -ForegroundColor Yellow
} else {
    Write-Host "  Result:     SURVIVED" -ForegroundColor Green
    $proc.CloseMainWindow() | Out-Null
    $proc.WaitForExit(5000) | Out-Null
    if (-not $proc.HasExited) { $proc.Kill() }
}

# --- Save logs ---
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
if (Test-Path $debugLog) {
    $destLog = Join-Path $outDir "stress_${timestamp}.log"
    Copy-Item $debugLog $destLog
    Write-Host "  Debug log:  $destLog" -ForegroundColor Gray

    $vehLines = Select-String -Path $destLog -Pattern "VEH Exception|UNHANDLED EXCEPTION|skipping focus"
    if ($vehLines) {
        Write-Host "  VEH/Guard:" -ForegroundColor Yellow
        $vehLines | ForEach-Object { Write-Host "    $($_.Line)" }
    }
}
Write-Host ""
