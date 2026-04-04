<#
.SYNOPSIS
    AUTONOMOUS MODE: Reproduce UI hang issue #197 / #198.
    Simulates AI agent activity: Rapid Title changes + Heavy scrolling + CP queries.
#>
param(
    [int]$Duration = 60,
    [int]$ReadThreads = 5,
    [int]$WriteThreads = 5,
    [switch]$NoBuild,
    [string]$ExePath = "zig-out-winui3\bin\ghostty.exe"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

# --- Win32 API ---
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class UIProbe {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    
    public const uint SMTO_ABORTIFHUNG = 0x0002;
    public const uint WM_NULL = 0x0000;
    public const uint WM_CHAR = 0x0102;
}
"@

if (-not $NoBuild) {
    Write-Host "[repro] Building..." -ForegroundColor Cyan
    Push-Location $repoRoot; bash -c "./build-winui3.sh" 2>&1 | Select-Object -Last 3; Pop-Location
}

$exe = Join-Path $repoRoot $ExePath
$env:GHOSTTY_CONTROL_PLANE = "1"
$proc = Start-Process -FilePath $exe -PassThru
Start-Sleep -Seconds 5
$hwnd = $proc.MainWindowHandle

# Find pipe
$sessDir = Join-Path $env:LOCALAPPDATA "ghostty\control-plane\winui3\sessions"
$sessFile = Get-ChildItem (Join-Path $sessDir "*.session") | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$pipePath = (Get-Content $sessFile.FullName | Select-String "pipe_path=").ToString().Split("=")[1]
Write-Host "[repro] Target Pipe: $pipePath" -ForegroundColor Green

# 1. Start HEAVY autonomous load inside terminal (Title changes + Scrolling)
# Note: uses write-host with ANSI escape for OSC 0 (set title)
$loadCmd = "powershell -NoProfile -Command `"for(`$i=0; `$true; `$i++){ [Console]::Write(`"`$([char]27)]0;AUTO_REPRO_TITLE_`$i`$([char]7)AUTO_REPRO_LOG_LINE_`$i`n`"); }`"`r"
foreach ($ch in $loadCmd.ToCharArray()) {
    [UIProbe]::PostMessage($hwnd, [UIProbe]::WM_CHAR, [IntPtr]::new([int]$ch), [IntPtr]::Zero) | Out-Null
}
Write-Host "[repro] Autonomous load started (Title + Scroll bombardment)" -ForegroundColor Yellow

# 2. Bombardment Scripts
$readScript = {
    param($pipePath, $duration)
    $startTime = [DateTime]::UtcNow
    while (([DateTime]::UtcNow - $startTime).TotalSeconds -lt $duration) {
        try {
            $pipe = [System.IO.Pipes.NamedPipeClientStream]::new(".", ($pipePath -replace '^\\\\\.\\pipe\\', ''), [System.IO.Pipes.PipeDirection]::InOut)
            $pipe.Connect(50)
            $writer = [System.IO.StreamWriter]::new($pipe); $reader = [System.IO.StreamReader]::new($pipe)
            $writer.WriteLine("TAIL|50"); $writer.Flush(); $null = $reader.ReadLine()
            $pipe.Close()
        } catch { }
    }
}

$writeScript = {
    param($pipePath, $duration)
    $startTime = [DateTime]::UtcNow
    while (([DateTime]::UtcNow - $startTime).TotalSeconds -lt $duration) {
        try {
            $pipe = [System.IO.Pipes.NamedPipeClientStream]::new(".", ($pipePath -replace '^\\\\\.\\pipe\\', ''), [System.IO.Pipes.PipeDirection]::InOut)
            $pipe.Connect(50)
            $writer = [System.IO.StreamWriter]::new($pipe); $reader = [System.IO.StreamReader]::new($pipe)
            $writer.WriteLine("INPUT|repro|YQo="); $writer.Flush(); $null = $reader.ReadLine()
            $pipe.Close()
        } catch { }
    }
}

# 3. Tab Shuffling Script (Stress App.surfaces list)
$tabScript = {
    param($pipePath, $duration)
    $startTime = [DateTime]::UtcNow
    while (([DateTime]::UtcNow - $startTime).TotalSeconds -lt $duration) {
        try {
            $pipe = [System.IO.Pipes.NamedPipeClientStream]::new(".", ($pipePath -replace '^\\\\\.\\pipe\\', ''), [System.IO.Pipes.PipeDirection]::InOut)
            $pipe.Connect(50)
            $writer = [System.IO.StreamWriter]::new($pipe); $reader = [System.IO.StreamReader]::new($pipe)
            # Create a tab, wait a bit, then close it
            $writer.WriteLine("NEW_TAB"); $writer.Flush(); $null = $reader.ReadLine()
            Start-Sleep -Milliseconds 100
            $writer.WriteLine("CLOSE_TAB|1"); $writer.Flush(); $null = $reader.ReadLine()
            $pipe.Close()
        } catch { }
        Start-Sleep -Milliseconds 50
    }
}

Write-Host "[repro] Launching Readers, Writers, and Tab Shufflers..." -ForegroundColor Red
$jobs = @()
for ($i=0; $i -lt $ReadThreads; $i++) { $jobs += Start-Job -ScriptBlock $readScript -ArgumentList $pipePath, $Duration }
for ($i=0; $i -lt $WriteThreads; $i++) { $jobs += Start-Job -ScriptBlock $writeScript -ArgumentList $pipePath, $Duration }
$jobs += Start-Job -ScriptBlock $tabScript -ArgumentList $pipePath, $Duration

# --- Monitor ---
$startTime = [DateTime]::UtcNow
$hangCount = 0
$checkCount = 0

Write-Host "[repro] Monitoring UI responsiveness..." -ForegroundColor Cyan

while (([DateTime]::UtcNow - $startTime).TotalSeconds -lt $Duration) {
    if ($proc.HasExited) { break }
    $res = [IntPtr]::Zero
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ok = [UIProbe]::SendMessageTimeout($hwnd, [UIProbe]::WM_NULL, [IntPtr]::Zero, [IntPtr]::Zero, [UIProbe]::SMTO_ABORTIFHUNG, 500, [ref]$res)
    $sw.Stop()
    $checkCount++
    if ($ok -eq [IntPtr]::Zero) {
        $hangCount++
        Write-Host "[repro] !!! HANG DETECTED !!! - #$hangCount" -ForegroundColor Red
    } elseif ($sw.ElapsedMilliseconds -gt 50) {
        Write-Host "[repro] UI Lag: $($sw.ElapsedMilliseconds)ms" -ForegroundColor Yellow
    }
    Start-Sleep -Milliseconds 50
}

# Cleanup
$jobs | Stop-Job | Remove-Job
if (-not $proc.HasExited) { $proc.Kill() }

Write-Host "`n=== Final Results ==="
Write-Host "  Checks: $checkCount"
Write-Host "  Hangs:  $hangCount"
if ($hangCount -gt 0) { Write-Host "  RESULT: REPRODUCED" -ForegroundColor Green }
else { Write-Host "  RESULT: STABLE" -ForegroundColor Cyan }
