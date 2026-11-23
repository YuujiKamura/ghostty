# test-14-tab-strip-width — however many tabs are open, the tab strip
# leaves room for the drag area (window can still be moved by its title
# bar) and never pushes the min / max / close buttons off the window.
#
# Axes: tab count {1, 2, 4, 6, 10} x window width {900, 1400 px}.
# Tabs are opened over the control plane (NEW_TAB); no keyboard / mouse.
# Captures %TEMP%\ghostty-test14-<width>-<tabs>.png for visual review.

param([string]$ExePath)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module "$PSScriptRoot\test-helpers.psm1" -Force -WarningAction SilentlyContinue

$testName = "test-14-tab-strip-width"
if (-not $ExePath) { $ExePath = Join-Path $PSScriptRoot "..\..\zig-out-winui3\bin\ghostty.exe" }
$ExePath = (Resolve-Path $ExePath -ErrorAction Stop).Path

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32T14 {
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int hh, uint f);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@ -ErrorAction SilentlyContinue

function Send-CP([int]$procId, [string]$cmd) {
    $pipe = [System.IO.Pipes.NamedPipeClientStream]::new(".", "ghostty-winui3-ghostty-$procId-$procId", [System.IO.Pipes.PipeDirection]::InOut)
    try {
        $pipe.Connect(3000)
        $b = [Text.Encoding]::UTF8.GetBytes("$cmd`n"); $pipe.Write($b, 0, $b.Length); $pipe.Flush()
        $buf = New-Object byte[] 1024; $n = $pipe.Read($buf, 0, 1024)
        return [Text.Encoding]::UTF8.GetString($buf, 0, $n).Trim()
    } finally { $pipe.Dispose() }
}

function Save-Capture([IntPtr]$hwnd, [string]$path) {
    $r = New-Object Win32T14+RECT; [Win32T14]::GetWindowRect($hwnd, [ref]$r) | Out-Null
    $bmp = New-Object System.Drawing.Bitmap ($r.Right - $r.Left), ($r.Bottom - $r.Top)
    $g = [System.Drawing.Graphics]::FromImage($bmp); $hdc = $g.GetHdc()
    [Win32T14]::PrintWindow($hwnd, $hdc, 2) | Out-Null; $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save($path); $bmp.Dispose()
}

$tabCounts = @(1, 2, 4, 6, 10)
$widths = @(900, 1400)

foreach ($w in $widths) {
    $proc = $null
    try {
        $env:KS_NO_ACTIVATE = "visible"
        try { $proc = Start-Process -FilePath $ExePath -PassThru } finally { Remove-Item Env:KS_NO_ACTIVATE -ErrorAction SilentlyContinue }
        $hwnd = Find-GhosttyWindow -ProcessId $proc.Id
        [Win32T14]::SetWindowPos($hwnd, [IntPtr]::Zero, 100, 80, $w, 700, 0x14) | Out-Null
        Start-Sleep -Seconds 3
        $scale = [Win32T14]::GetDpiForWindow($hwnd) / 96.0
        $have = 1
        foreach ($n in $tabCounts) {
            while ($have -lt $n) { Send-CP $proc.Id "NEW_TAB" | Out-Null; $have++; Start-Sleep -Milliseconds 600 }
            Start-Sleep -Milliseconds 1500

            $win = New-Object Win32T14+RECT; [Win32T14]::GetWindowRect($hwnd, [ref]$win) | Out-Null
            $elem = Find-GhosttyUIAElement -ProcessId $proc.Id
            $tabCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Tab)
            $tab = $elem.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $tabCond)
            Test-Assert -Condition ($null -ne $tab) -Message "$testName [${w}px, $n tabs] - tab strip found"
            $tabRight = $tab.Current.BoundingRectangle.Right
            # Caption buttons are 3 x 46 DIP at the right edge of the window.
            $captionLeft = $win.Right - (3 * 46 * $scale) - (12 * $scale)
            Test-Assert -Condition ($tabRight -le $captionLeft) -Message "$testName [${w}px, $n tabs] - tab strip ends before the caption buttons (tab right=$([int]$tabRight), caption left~$([int]$captionLeft))"

            $drag = Get-ChildWindowByClass -Hwnd $hwnd -ClassName "GhosttyDragBar"
            Test-Assert -Condition ($drag -ne [IntPtr]::Zero) -Message "$testName [${w}px, $n tabs] - drag bar window exists"
            $dr = New-Object Win32T14+RECT; [Win32T14]::GetWindowRect($drag, [ref]$dr) | Out-Null
            $dragW = $dr.Right - $dr.Left
            Test-Assert -Condition ([Win32T14]::IsWindowVisible($drag) -and $dragW -ge [int](40 * $scale)) -Message "$testName [${w}px, $n tabs] - drag area kept (width=$dragW px)"

            Save-Capture $hwnd (Join-Path $env:TEMP "ghostty-test14-$w-$n.png")
        }
        Test-Assert -Condition (-not $proc.HasExited) -Message "$testName [${w}px] - process alive"
    } finally {
        if ($proc) { Stop-Ghostty -Process $proc }
    }
}
Write-Host "PASS: $testName" -ForegroundColor Green
