<#
.SYNOPSIS
    Stress test for ghostty WinUI3: heavy output + window operations + pointer events.
    Reproduces the crash scenario where onXamlPointerPressed during maximize/restore
    causes a fatal exception.

.DESCRIPTION
    1. Launch ghostty WinUI3 with steady_load.py generating heavy output
    2. Simultaneously perform rapid window operations (maximize, restore, resize, move)
    3. Inject mouse click events during those operations
    4. Monitor for crashes and collect diagnostics

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
$debugLog = "$env:USERPROFILE\ghostty_debug.log"
$outDir = Join-Path $repoRoot "tmp\stress-test"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

# --- Win32 API ---
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Stress {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    public const int SW_MAXIMIZE = 3;
    public const int SW_RESTORE = 9;
    public const int SW_MINIMIZE = 6;
    public const uint WM_LBUTTONDOWN = 0x0201;
    public const uint WM_LBUTTONUP = 0x0202;
    public const uint WM_MOUSEMOVE = 0x0200;
    public const uint WM_SIZE = 0x0005;

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

$exe = Join-Path $repoRoot $ExePath
if (-not (Test-Path $exe)) {
    Write-Error "ghostty.exe not found at $exe"
    return
}

# --- Clear old log ---
if (Test-Path $debugLog) {
    $backupLog = Join-Path $outDir "pre_stress_debug.log"
    Copy-Item $debugLog $backupLog -Force
    Remove-Item $debugLog -Force
}

# --- Launch ghostty with steady_load ---
Write-Host "[stress] Launching ghostty + steady_load.py ($Duration sec)..." -ForegroundColor Cyan
$env:GHOSTTY_WINUI3_ENABLE_TABVIEW = "1"
$env:GHOSTTY_WINUI3_ENABLE_TABVIEW_HANDLERS = "1"

# Start ghostty; it runs steady_load.py as the shell command
$proc = Start-Process -FilePath $exe -ArgumentList @(
    "-e", "python", "$repoRoot\scripts\steady_load.py", "$Duration"
) -PassThru

# Wait for window to appear
$hwnd = [IntPtr]::Zero
$maxWait = 15
for ($i = 0; $i -lt $maxWait; $i++) {
    Start-Sleep -Seconds 1
    if ($proc.HasExited) {
        Write-Error "[stress] ghostty exited before window appeared (exit=$($proc.ExitCode))"
        return
    }
    # Find window by process
    $hwnd = $proc.MainWindowHandle
    if ($hwnd -ne [IntPtr]::Zero) { break }
}
if ($hwnd -eq [IntPtr]::Zero) {
    Write-Warning "[stress] Could not find ghostty window handle, trying FindWindow..."
    $hwnd = [Win32Stress]::FindWindow($null, "ghostty")
}
if ($hwnd -eq [IntPtr]::Zero) {
    Write-Error "[stress] No window found after ${maxWait}s"
    return
}
Write-Host "[stress] Window found: 0x$($hwnd.ToString('X'))" -ForegroundColor Green

# --- Stress loop ---
$rng = [System.Random]::new()
$startTime = [DateTime]::UtcNow
$opCount = 0
$crashDetected = $false

Write-Host "[stress] Starting window operations for $Duration seconds..." -ForegroundColor Yellow

while (([DateTime]::UtcNow - $startTime).TotalSeconds -lt $Duration) {
    if ($proc.HasExited) {
        $crashDetected = $true
        Write-Host "[stress] CRASH DETECTED at op #$opCount (exit=$($proc.ExitCode))" -ForegroundColor Red
        break
    }

    $op = $rng.Next(6)
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
        3 { # Inject mouse click at random position in client area
            $x = $rng.Next(10, 800)
            $y = $rng.Next(10, 600)
            $lp = [Win32Stress]::MakeLParam($x, $y)
            [Win32Stress]::PostMessage($hwnd, [Win32Stress]::WM_LBUTTONDOWN, [IntPtr]::new(1), $lp) | Out-Null
            Start-Sleep -Milliseconds 10
            [Win32Stress]::PostMessage($hwnd, [Win32Stress]::WM_LBUTTONUP, [IntPtr]::Zero, $lp) | Out-Null
        }
        4 { # Rapid maximize-restore (the exact crash trigger)
            [Win32Stress]::ShowWindow($hwnd, [Win32Stress]::SW_MAXIMIZE) | Out-Null
            Start-Sleep -Milliseconds 50
            [Win32Stress]::ShowWindow($hwnd, [Win32Stress]::SW_RESTORE) | Out-Null
            Start-Sleep -Milliseconds 50
            # Click immediately after restore
            $lp = [Win32Stress]::MakeLParam(400, 300)
            [Win32Stress]::PostMessage($hwnd, [Win32Stress]::WM_LBUTTONDOWN, [IntPtr]::new(1), $lp) | Out-Null
        }
        5 { # Mouse move sweep
            for ($m = 0; $m -lt 10; $m++) {
                $x = $rng.Next(0, 1000)
                $y = $rng.Next(0, 700)
                $lp = [Win32Stress]::MakeLParam($x, $y)
                [Win32Stress]::PostMessage($hwnd, [Win32Stress]::WM_MOUSEMOVE, [IntPtr]::Zero, $lp) | Out-Null
            }
        }
    }
    $opCount++
    Start-Sleep -Milliseconds ($rng.Next(30, 200))
}

# --- Collect results ---
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
    # Graceful shutdown
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

    # Check for VEH exceptions
    $vehLines = Select-String -Path $destLog -Pattern "VEH Exception|UNHANDLED EXCEPTION|skipping focus"
    if ($vehLines) {
        Write-Host "  VEH/Guard hits:" -ForegroundColor Yellow
        $vehLines | ForEach-Object { Write-Host "    $($_.Line)" }
    }
}

Write-Host ""
