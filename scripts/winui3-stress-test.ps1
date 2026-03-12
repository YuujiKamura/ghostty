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

# --- WARNING: This test grabs mouse cursor and foreground window ---
Write-Host ""
Write-Host "WARNING: This test uses SendInput to inject real mouse clicks." -ForegroundColor Red
Write-Host "         Your mouse cursor WILL be moved during the test." -ForegroundColor Red
Write-Host "         Do not touch mouse/keyboard for $Duration seconds." -ForegroundColor Red
Write-Host ""
$confirm = Read-Host "Continue? (y/N)"
if ($confirm -ne "y") {
    Write-Host "Aborted." -ForegroundColor Yellow
    return
}

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

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT {
        public uint type;
        public MOUSEINPUT mi;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll")] public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);

    public const uint INPUT_MOUSE = 0;
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public const uint MOUSEEVENTF_ABSOLUTE = 0x8000;
    public const uint MOUSEEVENTF_MOVE = 0x0001;

    public static void RealClick(IntPtr hwnd, int clientX, int clientY) {
        RECT r;
        GetWindowRect(hwnd, out r);
        int screenX = r.Left + clientX;
        int screenY = r.Top + clientY;
        SetCursorPos(screenX, screenY);
        INPUT[] inputs = new INPUT[2];
        inputs[0].type = INPUT_MOUSE;
        inputs[0].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
        inputs[1].type = INPUT_MOUSE;
        inputs[1].mi.dwFlags = MOUSEEVENTF_LEFTUP;
        SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
    }

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

# Start ghostty (plain launch — no -e flag, WinUI3 doesn't support it).
# Output load will be injected via a separate process writing to a pipe,
# or we rely on the terminal's own shell activity as the load source.
$proc = Start-Process -FilePath $exe -PassThru

# Wait for window to appear
$hwnd = [IntPtr]::Zero
$maxWait = 20
for ($i = 0; $i -lt $maxWait; $i++) {
    Start-Sleep -Seconds 1
    if ($proc.HasExited) {
        Write-Error "[stress] ghostty exited before window appeared (exit=$($proc.ExitCode))"
        return
    }
    # Refresh process info to get MainWindowHandle
    $proc = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
    if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) {
        $hwnd = $proc.MainWindowHandle
        break
    }
}
if ($hwnd -eq [IntPtr]::Zero) {
    Write-Warning "[stress] MainWindowHandle not found, trying FindWindow..."
    # Try common WinUI3 window class names
    foreach ($title in @("ghostty", "Ghostty", "")) {
        $hwnd = [Win32Stress]::FindWindow($null, $title)
        if ($hwnd -ne [IntPtr]::Zero) { break }
    }
}
if ($hwnd -eq [IntPtr]::Zero) {
    Write-Error "[stress] No window found after ${maxWait}s"
    return
}
Write-Host "[stress] Window found: 0x$($hwnd.ToString('X'))" -ForegroundColor Green

# Inject output load: type a command into the terminal via keystroke injection
Start-Sleep -Seconds 2
$loadCmd = "python $($repoRoot -replace '\\','/')/scripts/steady_load.py $Duration"
foreach ($ch in $loadCmd.ToCharArray()) {
    # WM_CHAR to send each character
    [Win32Stress]::PostMessage($hwnd, 0x0102, [IntPtr]::new([int]$ch), [IntPtr]::Zero) | Out-Null
}
# Send Enter (VK_RETURN = 0x0D)
[Win32Stress]::PostMessage($hwnd, 0x0102, [IntPtr]::new(0x0D), [IntPtr]::Zero) | Out-Null
Write-Host "[stress] Injected output load command" -ForegroundColor Green
Start-Sleep -Seconds 2

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
        3 { # Real mouse click via SendInput (reaches XAML pointer layer)
            [Win32Stress]::SetForegroundWindow($hwnd) | Out-Null
            $x = $rng.Next(50, 600)
            $y = $rng.Next(50, 400)
            [Win32Stress]::RealClick($hwnd, $x, $y)
        }
        4 { # Rapid maximize-restore + real click (exact crash trigger)
            [Win32Stress]::ShowWindow($hwnd, [Win32Stress]::SW_MAXIMIZE) | Out-Null
            Start-Sleep -Milliseconds 50
            [Win32Stress]::ShowWindow($hwnd, [Win32Stress]::SW_RESTORE) | Out-Null
            Start-Sleep -Milliseconds 50
            # Real click immediately after restore
            [Win32Stress]::SetForegroundWindow($hwnd) | Out-Null
            [Win32Stress]::RealClick($hwnd, 400, 300)
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
