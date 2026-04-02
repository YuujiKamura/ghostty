# Launch ghostty and run ghost_demo inside it via SendKeys
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W32Demo {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EWP cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    public delegate bool EWP(IntPtr h, IntPtr l);
}
"@

$ghosttyExe = Join-Path $PSScriptRoot "..\..\zig-out-winui3\bin\ghostty.exe"

# Kill existing
Stop-Process -Name ghostty -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Launch
$proc = Start-Process -FilePath $ghosttyExe -PassThru
Write-Host "Ghostty PID: $($proc.Id)"
Start-Sleep -Seconds 10

# Find window
$targetHwnd = [IntPtr]::Zero
$gpid = $proc.Id
[W32Demo]::EnumWindows({
    param($hw, $lp)
    $wp = 0
    [W32Demo]::GetWindowThreadProcessId($hw, [ref]$wp) | Out-Null
    if ($wp -eq $gpid -and [W32Demo]::IsWindowVisible($hw)) {
        $script:targetHwnd = $hw
        return $false
    }
    return $true
}, [IntPtr]::Zero)

if ($targetHwnd -eq [IntPtr]::Zero) {
    Write-Host "ERROR: no ghostty window found"
    exit 1
}

Write-Host "Window: 0x$($targetHwnd.ToString('X'))"
[W32Demo]::SetForegroundWindow($targetHwnd) | Out-Null
Start-Sleep -Milliseconds 1000

# Send command via SendKeys (python play.py is more robust than ghost_demo.exe)
$demoCmd = "python $($PSScriptRoot)\play.py --fps 15"
[System.Windows.Forms.SendKeys]::SendWait($demoCmd)
Start-Sleep -Milliseconds 300
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Write-Host "OK: demo command sent to ghostty"
