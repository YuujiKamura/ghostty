# test-11-window-stack — a newly launched ghostty window opens stacked on
# the existing GhosttyWindow: same position, same size.
# Covers island_window.zig makeWindow() FindWindowW/GetWindowRect inheritance.
#
# Self-launches two ghostty instances and stops both (works even when other
# GhosttyWindow processes — e.g. deckpilot workers — are alive: instance #1
# is moved to a unique rect and raised to the top of the Z order, so the
# inherited rect can only come from it, not by coincidence).
# No mouse input (SetWindowPos/MoveWindow only).

param([string]$ExePath)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module "$PSScriptRoot\test-helpers.psm1" -Force

$testName = "test-11-window-stack"

if (-not $ExePath) {
    $ExePath = Join-Path $PSScriptRoot "..\..\zig-out-winui3\bin\ghostty.exe"
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Stack {
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hwnd, IntPtr insertAfter, int x, int y, int w, int h, uint flags);
    public static readonly IntPtr HWND_TOP = IntPtr.Zero;
    public const uint SWP_NOSIZE     = 0x0001;
    public const uint SWP_NOMOVE     = 0x0002;
    public const uint SWP_NOACTIVATE = 0x0010;
}
"@ -ErrorAction SilentlyContinue

# Unique rect — odd values no real window would have by accident.
$ux = 173; $uy = 142; $uw = 917; $uh = 643

$proc1 = $null
$proc2 = $null
try {
    Write-Host "  Launching ghostty #1 ..." -ForegroundColor Cyan
    $proc1 = Start-Ghostty -ExePath $ExePath
    Write-Host "  #1 PID=$($proc1.Id)" -ForegroundColor DarkGray
    $hwnd1 = Find-GhosttyWindow -ProcessId $proc1.Id -TimeoutMs 15000

    # Move #1 to the unique rect and raise it to the top of the Z order
    # without activating, so makeWindow's FindWindowW in the next process
    # finds #1 first.
    [Win32]::MoveWindow($hwnd1, $ux, $uy, $uw, $uh, $true) | Out-Null
    [Win32Stack]::SetWindowPos($hwnd1, [Win32Stack]::HWND_TOP, 0, 0, 0, 0,
        ([Win32Stack]::SWP_NOMOVE -bor [Win32Stack]::SWP_NOSIZE -bor [Win32Stack]::SWP_NOACTIVATE)) | Out-Null
    Start-Sleep -Milliseconds 300

    $r1 = Get-WindowPosition -Hwnd $hwnd1
    Test-AssertEqual -Expected $ux -Actual $r1.Left   -Message "$testName - #1 at unique X"
    Test-AssertEqual -Expected $uy -Actual $r1.Top    -Message "$testName - #1 at unique Y"
    Test-AssertEqual -Expected $uw -Actual $r1.Width  -Message "$testName - #1 at unique width"
    Test-AssertEqual -Expected $uh -Actual $r1.Height -Message "$testName - #1 at unique height"

    Write-Host "  Launching ghostty #2 ..." -ForegroundColor Cyan
    $proc2 = Start-Ghostty -ExePath $ExePath
    Write-Host "  #2 PID=$($proc2.Id)" -ForegroundColor DarkGray
    $hwnd2 = Find-GhosttyWindow -ProcessId $proc2.Id -TimeoutMs 15000
    Start-Sleep -Milliseconds 500  # let initial sizing settle

    $r2 = Get-WindowPosition -Hwnd $hwnd2
    Test-AssertEqual -Expected $r1.Left   -Actual $r2.Left   -Message "$testName - #2 inherits X from #1"
    Test-AssertEqual -Expected $r1.Top    -Actual $r2.Top    -Message "$testName - #2 inherits Y from #1"
    Test-AssertEqual -Expected $r1.Width  -Actual $r2.Width  -Message "$testName - #2 inherits width from #1"
    Test-AssertEqual -Expected $r1.Height -Actual $r2.Height -Message "$testName - #2 inherits height from #1"

    Write-Host "PASS: $testName - new window stacked on existing window (same rect)" -ForegroundColor Green
} finally {
    if ($proc2) { Stop-Ghostty -Process $proc2 }
    if ($proc1) { Stop-Ghostty -Process $proc1 }
}
