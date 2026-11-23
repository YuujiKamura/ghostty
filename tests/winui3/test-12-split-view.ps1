# test-12-split-view — split view shows every tab (up to 4) at once, each
# pane with a one-line header ("1  title" ...); the tab strip is unchanged.
#
# Axes: mode {none, top_bottom, left_right, grid} x tab count {1..5} via
# NEW_TAB / SWITCH_TAB / CLOSE_TAB on the control plane. Split is opened via the
# KS_SPLIT_VIEW launch env var (App.applyLaunchSplitMode) so no keys are
# sent to whatever window is in the foreground. No mouse input.
#
# For every mode the window is captured (PrintWindow, no activation) to
# %TEMP%\ghostty-test12-<mode>.png for visual review.

param([string]$ExePath)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Import-Module "$PSScriptRoot\test-helpers.psm1" -Force

$testName = "test-12-split-view"

if (-not $ExePath) {
    $ExePath = Join-Path $PSScriptRoot "..\..\zig-out-winui3\bin\ghostty.exe"
}
$ExePath = (Resolve-Path $ExePath -ErrorAction Stop).Path

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Split {
    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hwnd, IntPtr insertAfter, int x, int y, int w, int h, uint flags);
    public const uint SWP_NOACTIVATE = 0x0010;
    public const uint SWP_NOZORDER   = 0x0004;
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
}
"@ -ErrorAction SilentlyContinue

function Save-WindowCapture([IntPtr]$hwnd, [string]$path) {
    $r = New-Object Win32Split+RECT
    [Win32Split]::GetWindowRect($hwnd, [ref]$r) | Out-Null
    $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    [Win32Split]::PrintWindow($hwnd, $hdc, 2) | Out-Null  # PW_RENDERFULLCONTENT
    $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

function Get-TextNames($elem) {
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Text)
    $all = $elem.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
    $names = @()
    foreach ($e in $all) { $names += $e.Current.Name }
    return ,$names
}

function Get-TabItemCount($elem) {
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::TabItem)
    return $elem.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond).Count
}

# Send one control-plane command (NEW_TAB / SWITCH_TAB|n / CLOSE_TAB|n).
# These run the same App paths as the tab strip and keyboard shortcuts.
function Send-CPCommand([int]$procId, [string]$cmd) {
    $pipeName = "ghostty-winui3-ghostty-$procId-$procId"
    $pipe = [System.IO.Pipes.NamedPipeClientStream]::new(".", $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
    try {
        $pipe.Connect(3000)
        $req = [System.Text.Encoding]::UTF8.GetBytes("$cmd`n")
        $pipe.Write($req, 0, $req.Length); $pipe.Flush()
        $buf = New-Object byte[] 65536
        $n = $pipe.Read($buf, 0, $buf.Length)
        return [System.Text.Encoding]::UTF8.GetString($buf, 0, $n).Trim()
    } finally { $pipe.Dispose() }
}

# Tab numbers ("1", "3", ...) shown in the split headers, sorted.
function Get-HeaderNumbers($elem) {
    $texts = Get-TextNames $elem
    $nums = @($texts | Where-Object { $_ -match '^[0-9]+  ' } | ForEach-Object { [int]($_ -split '  ')[0] } | Sort-Object)
    return ($nums -join ',')
}

# Tab-count steps after launch (2 tabs, tab 2 focused). Expected header
# numbers = the shown window of up to 4 consecutive tabs that contains the
# focused tab (split_view.windowStart).
$steps = @(
    @{ Cmd = "NEW_TAB";      Expect = "1,2,3";   Why = "3 tabs: all shown" },
    @{ Cmd = "NEW_TAB";      Expect = "1,2,3,4"; Why = "4 tabs: all shown"; Capture = "4tabs" },
    @{ Cmd = "NEW_TAB";      Expect = "2,3,4,5"; Why = "5 tabs: cap 4, window follows the new tab" },
    @{ Cmd = "SWITCH_TAB|0"; Expect = "1,2,3,4"; Why = "selecting a hidden tab pages the window back" },
    @{ Cmd = "SWITCH_TAB|2"; Expect = "1,2,3,4"; Why = "selecting a shown tab keeps the window" },
    @{ Cmd = "CLOSE_TAB|4";  Expect = "1,2,3,4"; Why = "back to 4 tabs" },
    @{ Cmd = "CLOSE_TAB|3";  Expect = "1,2,3";   Why = "3 tabs"; Capture = "3tabs" },
    @{ Cmd = "CLOSE_TAB|2";  Expect = "1,2";     Why = "2 tabs" },
    @{ Cmd = "CLOSE_TAB|1";  Expect = "";        Why = "one tab left: split view off" }
)

$modes = @(
    @{ Name = "none";       Env = "";           Tabs = 1; Headers = 0 },
    @{ Name = "top_bottom"; Env = "top_bottom"; Tabs = 2; Headers = 2 },
    @{ Name = "left_right"; Env = "left_right"; Tabs = 2; Headers = 2 },
    @{ Name = "grid";       Env = "grid";       Tabs = 2; Headers = 2 }
)

foreach ($m in $modes) {
    $proc = $null
    try {
        Write-Host "  [$($m.Name)] launching ..." -ForegroundColor DarkGray
        $env:KS_NO_ACTIVATE = "visible"
        if ($m.Env) { $env:KS_SPLIT_VIEW = $m.Env } else { Remove-Item Env:KS_SPLIT_VIEW -ErrorAction SilentlyContinue }
        try {
            $proc = Start-Process -FilePath $ExePath -PassThru
        } finally {
            Remove-Item Env:KS_NO_ACTIVATE -ErrorAction SilentlyContinue
            Remove-Item Env:KS_SPLIT_VIEW -ErrorAction SilentlyContinue
        }

        $hwnd = Find-GhosttyWindow -ProcessId $proc.Id
        [Win32Split]::SetWindowPos($hwnd, [IntPtr]::Zero, 120, 90, 1400, 1000,
            ([Win32Split]::SWP_NOACTIVATE -bor [Win32Split]::SWP_NOZORDER)) | Out-Null
        Start-Sleep -Milliseconds 2500

        Test-Assert -Condition (-not $proc.HasExited) -Message "$testName [$($m.Name)] - process alive after launch"

        $elem = Find-GhosttyUIAElement -ProcessId $proc.Id
        $tabs = Get-TabItemCount $elem
        Test-AssertEqual -Expected $m.Tabs -Actual $tabs -Message "$testName [$($m.Name)] - TabItem count"

        $texts = Get-TextNames $elem
        $headers = @($texts | Where-Object { $_ -match '^[0-9]+  ' })
        Write-Host "  [$($m.Name)] header texts: $($headers -join ' | ')" -ForegroundColor Cyan
        Test-AssertEqual -Expected $m.Headers -Actual $headers.Count -Message "$testName [$($m.Name)] - split header count"
        if ($m.Headers -eq 2) {
            # Each pane's shell titles its own tab (set_title is routed by
            # target surface, not to the active tab): no "N  Tab N" fallback.
            foreach ($h in $headers) {
                Test-Assert -Condition ($h -notmatch '^([0-9]+)  Tab \1$') -Message "$testName [$($m.Name)] - header has shell title ('$h')"
            }
        }

        $png = Join-Path $env:TEMP "ghostty-test12-$($m.Name).png"
        Save-WindowCapture $hwnd $png
        Write-Host "  [$($m.Name)] capture: $png" -ForegroundColor DarkGray

        if ($m.Headers -eq 2) {
            $i = 0
            foreach ($st in $steps) {
                $i++
                $resp = Send-CPCommand $proc.Id $st.Cmd
                Start-Sleep -Milliseconds 1500
                Test-Assert -Condition (-not $proc.HasExited) -Message "$testName [$($m.Name)] step $i $($st.Cmd) - process alive (resp=$resp)"
                $got = Get-HeaderNumbers (Find-GhosttyUIAElement -ProcessId $proc.Id)
                Test-AssertEqual -Expected $st.Expect -Actual $got -Message "$testName [$($m.Name)] step $i $($st.Cmd) - headers ($($st.Why))"
                if ($st.ContainsKey('Capture') -and $st.Capture -eq '4tabs') {
                    # Background-tab input while split: tab 1 is shown but not
                    # focused (tab 4 is). Input addressed to tab 0 lands there only.
                    $marker = "RT$(Get-Random -Minimum 10000 -Maximum 99999)"  # short: narrow panes wrap long lines
                    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("echo $marker`r"))
                    $r = Send-CPCommand $proc.Id "INPUT|test12|$b64|0"
                    Start-Sleep -Milliseconds 1500
                    $t0 = ''; $t3 = ''
                    for ($k = 0; $k -lt 10; $k++) { $t0 = Send-CPCommand $proc.Id "CAPTURE_PANE|0"; if ($t0 -notmatch 'BUSY') { break }; Start-Sleep -Milliseconds 200 }
                    for ($k = 0; $k -lt 10; $k++) { $t3 = Send-CPCommand $proc.Id "CAPTURE_PANE|3"; if ($t3 -notmatch 'BUSY') { break }; Start-Sleep -Milliseconds 200 }
                    $t0 = $t0 -replace '\s', ''; $t3 = $t3 -replace '\s', ''
                    Test-Assert -Condition ($t0 -like "*$marker*") -Message "$testName [$($m.Name)] - input to background tab 1 lands in tab 1 (resp=$r)"
                    Test-Assert -Condition ($t3 -notlike "*$marker*") -Message "$testName [$($m.Name)] - focused tab 4 does not get tab 1's input"
                }
                if ($st.ContainsKey('Capture')) {
                    $png2 = Join-Path $env:TEMP "ghostty-test12-$($m.Name)-$($st.Capture).png"
                    Save-WindowCapture $hwnd $png2
                    Write-Host "  [$($m.Name)] capture: $png2" -ForegroundColor DarkGray
                }
            }
        }

        Test-Assert -Condition (-not $proc.HasExited) -Message "$testName [$($m.Name)] - process alive after checks"
    } finally {
        if ($proc) { Stop-Ghostty -Process $proc }
    }
}

Write-Host "PASS: $testName" -ForegroundColor Green
