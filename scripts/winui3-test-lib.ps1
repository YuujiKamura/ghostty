$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Win32 P/Invoke (C# helpers for struct construction)
# ---------------------------------------------------------------------------
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct KEYBDINPUT {
    public ushort wVk;
    public ushort wScan;
    public uint   dwFlags;
    public uint   time;
    public IntPtr dwExtraInfo;
}

[StructLayout(LayoutKind.Sequential)]
public struct MOUSEINPUT {
    public int    dx;
    public int    dy;
    public uint   mouseData;
    public uint   dwFlags;
    public uint   time;
    public IntPtr dwExtraInfo;
}

[StructLayout(LayoutKind.Sequential)]
public struct HARDWAREINPUT {
    public uint   uMsg;
    public ushort wParamL;
    public ushort wParamH;
}

[StructLayout(LayoutKind.Explicit)]
public struct INPUTUNION {
    [FieldOffset(0)] public MOUSEINPUT    mi;
    [FieldOffset(0)] public KEYBDINPUT    ki;
    [FieldOffset(0)] public HARDWAREINPUT hi;
}

[StructLayout(LayoutKind.Sequential)]
public struct INPUT {
    public uint       type;
    public INPUTUNION u;
    public const uint INPUT_KEYBOARD = 1;
}

[StructLayout(LayoutKind.Sequential)]
public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}

public static class Win32 {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr FindWindowW(string lpClassName, string lpWindowName);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetWindowPos(
        IntPtr hWnd, IntPtr hWndInsertAfter,
        int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetCursorPos(int X, int Y);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    public const uint KEYEVENTF_KEYUP      = 0x0002;
    public const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
    public const uint SWP_NOZORDER  = 0x0004;
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP   = 0x0004;
    public const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    public const uint MOUSEEVENTF_RIGHTUP   = 0x0010;
    public const uint MOUSEEVENTF_WHEEL    = 0x0800;

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

    public static bool ForceForegroundWindow(IntPtr hWnd) {
        uint targetPid;
        uint targetTid = GetWindowThreadProcessId(hWnd, out targetPid);
        uint currentTid = GetCurrentThreadId();
        bool attached = false;
        if (targetTid != currentTid) {
            attached = AttachThreadInput(currentTid, targetTid, true);
        }
        bool result = SetForegroundWindow(hWnd);
        if (attached) {
            AttachThreadInput(currentTid, targetTid, false);
        }
        return result;
    }

    public static uint SendKeysSequence(ushort[] vkCodes) {
        int count = vkCodes.Length * 2;
        INPUT[] inputs = new INPUT[count];
        int cbSize = Marshal.SizeOf(typeof(INPUT));
        for (int i = 0; i < vkCodes.Length; i++) {
            inputs[i * 2] = MakeKeyInput(vkCodes[i], 0);
            inputs[i * 2 + 1] = MakeKeyInput(vkCodes[i], KEYEVENTF_KEYUP);
        }
        return SendInput((uint)count, inputs, cbSize);
    }

    public static uint SendKeyCombo(ushort modifier, ushort key) {
        INPUT[] inputs = new INPUT[4];
        int cbSize = Marshal.SizeOf(typeof(INPUT));
        inputs[0] = MakeKeyInput(modifier, 0);
        inputs[1] = MakeKeyInput(key, 0);
        inputs[2] = MakeKeyInput(key, KEYEVENTF_KEYUP);
        inputs[3] = MakeKeyInput(modifier, KEYEVENTF_KEYUP);
        return SendInput(4, inputs, cbSize);
    }

    private static INPUT MakeKeyInput(ushort vk, uint flags) {
        INPUT inp = new INPUT();
        inp.type = INPUT.INPUT_KEYBOARD;
        inp.u.ki.wVk = vk;
        inp.u.ki.dwFlags = flags;
        return inp;
    }

    public static bool ClickWindowCenter(IntPtr hWnd) {
        RECT r;
        if (!GetWindowRect(hWnd, out r)) {
            return false;
        }
        int cx = r.Left + ((r.Right - r.Left) / 2);
        int cy = r.Top + ((r.Bottom - r.Top) / 2);
        if (!SetCursorPos(cx, cy)) {
            return false;
        }
        mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
        mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
        return true;
    }

    public static bool RightClickWindowCenter(IntPtr hWnd) {
        RECT r;
        if (!GetWindowRect(hWnd, out r)) {
            return false;
        }
        int cx = r.Left + ((r.Right - r.Left) / 2);
        int cy = r.Top + ((r.Bottom - r.Top) / 2);
        if (!SetCursorPos(cx, cy)) {
            return false;
        }
        mouse_event(MOUSEEVENTF_RIGHTDOWN, 0, 0, 0, UIntPtr.Zero);
        mouse_event(MOUSEEVENTF_RIGHTUP, 0, 0, 0, UIntPtr.Zero);
        return true;
    }

    public static void WheelVertical(int delta) {
        mouse_event(MOUSEEVENTF_WHEEL, 0, 0, (uint)delta, UIntPtr.Zero);
    }
}
"@ -ErrorAction SilentlyContinue

try {
    Add-Type -AssemblyName System.Drawing | Out-Null
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
} catch {}

# ---------------------------------------------------------------------------
# Exit code decoding
# ---------------------------------------------------------------------------
$script:ExitCodeNames = @{
    0           = "SUCCESS"
    1           = "GENERAL_ERROR"
    -1          = "KILLED"
    -1073741189 = "STATUS_STOWED_EXCEPTION -- unhandled WinRT/COM exception"
    -1073741510 = "STATUS_CONTROL_C_EXIT"
    -1073741515 = "STATUS_DLL_NOT_FOUND"
    -1073741819 = "STATUS_ACCESS_VIOLATION"
    -1073740791 = "STATUS_STACK_OVERFLOW"
    -1073740940 = "STATUS_HEAP_CORRUPTION"
    -1073740771 = "STATUS_STACK_BUFFER_OVERRUN"
}

function Format-ExitCode([int]$code) {
    $hex = "0x{0:X8}" -f ([uint32]([BitConverter]::ToUInt32([BitConverter]::GetBytes($code), 0)))
    $name = $script:ExitCodeNames[$code]
    if ($name) { return "$code ($hex $name)" }
    return "$code ($hex)"
}

# ---------------------------------------------------------------------------
# Process lifecycle
# ---------------------------------------------------------------------------

function Start-Ghostty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ExePath,
        [Parameter(Mandatory)][string]$TmpDir,
        [string]$WorkingDirectory
    )

    if (-not (Test-Path $ExePath)) {
        throw "ghostty.exe not found: $ExePath"
    }

    if (-not $WorkingDirectory -or [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $WorkingDirectory = Split-Path -Parent $ExePath
    }

    New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $stderrPath = Join-Path $TmpDir "ghostty-stderr-$timestamp.log"
    "" | Set-Content -Path $stderrPath -Encoding utf8

    $proc = Start-Process -FilePath $ExePath `
        -WorkingDirectory $WorkingDirectory `
        -RedirectStandardError $stderrPath `
        -PassThru

    return [PSCustomObject]@{
        Process    = $proc
        StderrPath = $stderrPath
        StartTime  = Get-Date
    }
}

function Stop-Ghostty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Session,
        [int]$TimeoutMs = 5000
    )

    $proc = $Session.Process
    if ($proc.HasExited) { return $proc.ExitCode }

    try { $proc.CloseMainWindow() | Out-Null } catch {}

    if (-not $proc.WaitForExit($TimeoutMs)) {
        try { $proc.Kill(); $proc.WaitForExit(2000) | Out-Null } catch {}
    }
    return $proc.ExitCode
}

# ---------------------------------------------------------------------------
# Log monitoring (incremental read via FileStream)
# ---------------------------------------------------------------------------

function Wait-LogLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Pattern,
        [int]$TimeoutMs = 10000
    )

    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    $position = 0
    $buffer = ""

    while ((Get-Date) -lt $deadline) {
        if (Test-Path $Path) {
            try {
                $fs = [System.IO.FileStream]::new(
                    $Path,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read,
                    [System.IO.FileShare]::ReadWrite)
                try {
                    if ($fs.Length -gt $position) {
                        $fs.Position = $position
                        $reader = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8, $false, 4096, $true)
                        $newText = $reader.ReadToEnd()
                        $reader.Dispose()
                        $position = $fs.Length

                        $buffer += $newText
                        $lines = $buffer -split "\r?\n"
                        $buffer = $lines[-1]
                        for ($i = 0; $i -lt $lines.Length - 1; $i++) {
                            if ($lines[$i] -match $Pattern) {
                                return $lines[$i]
                            }
                        }
                    }
                } finally {
                    $fs.Dispose()
                }
            } catch {
                # File locked — retry next cycle
            }
        }
        Start-Sleep -Milliseconds 100
    }
    throw "Wait-LogLine timeout (${TimeoutMs}ms): pattern '$Pattern' not found in $Path"
}

# ---------------------------------------------------------------------------
# Window detection
#
# NOTE: WinUI3 windows are NOT discoverable via FindWindow or EnumWindows.
# GetWindowThreadProcessId returns 0 for WinUI3 HWNDs, making PID-based
# enumeration impossible. Parsing the HWND from Ghostty's own stderr log
# (step 4 OK: HWND=0x...) is the only reliable method confirmed by testing.
# If this log format changes, this function must be updated in lockstep.
# ---------------------------------------------------------------------------

function Find-GhosttyWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StderrPath,
        [int]$TimeoutMs = 10000
    )

    $line = Wait-LogLine -Path $StderrPath -Pattern "step 4 OK: HWND=0x" -TimeoutMs $TimeoutMs
    if ($line -match "HWND=0x([0-9a-fA-F]+)") {
        $hwnd = [IntPtr][System.Convert]::ToInt64($Matches[1], 16)
        if ([Win32]::IsWindowVisible($hwnd)) {
            return $hwnd
        }
        throw "HWND 0x$($Matches[1]) found in log but IsWindowVisible=false"
    }
    throw "Find-GhosttyWindow: HWND not found in log"
}

# ---------------------------------------------------------------------------
# Input simulation
# ---------------------------------------------------------------------------

function Send-Keys {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][UInt16[]]$Keys
    )

    $sent = [Win32]::SendKeysSequence($Keys)
    if ($sent -eq 0) {
        throw "SendInput returned 0 -- no events injected (is the window focused?)"
    }
    return $sent
}

function Send-KeyCombo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][UInt16]$Modifier,
        [Parameter(Mandatory)][UInt16]$Key
    )

    $sent = [Win32]::SendKeyCombo($Modifier, $Key)
    if ($sent -eq 0) {
        throw "SendInput returned 0 -- no events injected (is the window focused?)"
    }
    return $sent
}

function Send-MouseClickCenter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd
    )

    if (-not [Win32]::ClickWindowCenter($Hwnd)) {
        throw "ClickWindowCenter failed"
    }
}

function Send-MouseRightClickCenter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd
    )

    if (-not [Win32]::RightClickWindowCenter($Hwnd)) {
        throw "RightClickWindowCenter failed"
    }
}

function Send-MouseWheel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$Delta
    )

    [Win32]::WheelVertical($Delta)
}

function Get-WindowVisualDiffRatio {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [int]$DelayMs = 1000,
        [int]$SampleStep = 8,
        [int]$ColorThreshold = 30
    )

    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue | Out-Null

    $rect = New-Object RECT
    if (-not [Win32]::GetWindowRect($Hwnd, [ref]$rect)) {
        throw "GetWindowRect failed for HWND=0x$($Hwnd.ToString('X'))"
    }
    $w = [Math]::Max(1, $rect.Right - $rect.Left)
    $h = [Math]::Max(1, $rect.Bottom - $rect.Top)

    $bmpA = New-Object System.Drawing.Bitmap($w, $h)
    $gA = [System.Drawing.Graphics]::FromImage($bmpA)
    $gA.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmpA.Size)
    $gA.Dispose()

    Start-Sleep -Milliseconds $DelayMs

    $bmpB = New-Object System.Drawing.Bitmap($w, $h)
    $gB = [System.Drawing.Graphics]::FromImage($bmpB)
    $gB.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmpB.Size)
    $gB.Dispose()

    $changed = 0
    $total = 0
    for ($y = 0; $y -lt $h; $y += $SampleStep) {
        for ($x = 0; $x -lt $w; $x += $SampleStep) {
            $c1 = $bmpA.GetPixel($x, $y)
            $c2 = $bmpB.GetPixel($x, $y)
            $delta = [Math]::Abs([int]$c1.R - [int]$c2.R) +
                     [Math]::Abs([int]$c1.G - [int]$c2.G) +
                     [Math]::Abs([int]$c1.B - [int]$c2.B)
            if ($delta -ge $ColorThreshold) { $changed++ }
            $total++
        }
    }

    $bmpA.Dispose()
    $bmpB.Dispose()

    if ($total -le 0) { return 0.0 }
    return ([double]$changed / [double]$total)
}

function Get-WindowVisualSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd
    )

    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue | Out-Null

    $rect = New-Object RECT
    if (-not [Win32]::GetWindowRect($Hwnd, [ref]$rect)) {
        throw "GetWindowRect failed for HWND=0x$($Hwnd.ToString('X'))"
    }
    $w = [Math]::Max(1, $rect.Right - $rect.Left)
    $h = [Math]::Max(1, $rect.Bottom - $rect.Top)
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
    $g.Dispose()
    return $bmp
}

function Get-VisualDiffRatioBetween {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Drawing.Bitmap]$Before,
        [Parameter(Mandatory)][System.Drawing.Bitmap]$After,
        [int]$SampleStep = 8,
        [int]$ColorThreshold = 30
    )

    $w = [Math]::Min($Before.Width, $After.Width)
    $h = [Math]::Min($Before.Height, $After.Height)
    if ($w -le 0 -or $h -le 0) { return 0.0 }

    $changed = 0
    $total = 0
    for ($y = 0; $y -lt $h; $y += $SampleStep) {
        for ($x = 0; $x -lt $w; $x += $SampleStep) {
            $c1 = $Before.GetPixel($x, $y)
            $c2 = $After.GetPixel($x, $y)
            $delta = [Math]::Abs([int]$c1.R - [int]$c2.R) +
                     [Math]::Abs([int]$c1.G - [int]$c2.G) +
                     [Math]::Abs([int]$c1.B - [int]$c2.B)
            if ($delta -ge $ColorThreshold) { $changed++ }
            $total++
        }
    }
    if ($total -le 0) { return 0.0 }
    return ([double]$changed / [double]$total)
}

# ---------------------------------------------------------------------------
# Diagnostics & reporting
# ---------------------------------------------------------------------------

function Write-CrashDiagnostics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Session
    )

    $code = $Session.Process.ExitCode
    $uptime = [int]((Get-Date) - $Session.StartTime).TotalMilliseconds

    [Console]::ForegroundColor = [ConsoleColor]::Magenta
    [Console]::WriteLine("  --- Crash Diagnostics ---")
    [Console]::WriteLine("  Exit code : $(Format-ExitCode $code)")
    [Console]::WriteLine("  Uptime    : ${uptime}ms")

    if (Test-Path $Session.StderrPath) {
        $lines = @(Get-Content -Path $Session.StderrPath -Tail 10 -ErrorAction SilentlyContinue)
        if ($lines.Count -gt 0) {
            [Console]::WriteLine("  Last stderr lines:")
            foreach ($l in $lines) {
                [Console]::WriteLine("    $l")
            }
        }
    }
    [Console]::WriteLine("  --------------------------")
    [Console]::ResetColor()
}

function Clear-OldLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TmpDir,
        [int]$KeepCount = 5
    )

    if (-not (Test-Path $TmpDir)) { return }
    $logs = Get-ChildItem -Path $TmpDir -Filter "ghostty-stderr-*.log" |
            Sort-Object -Property LastWriteTime -Descending
    if ($logs.Count -gt $KeepCount) {
        $logs | Select-Object -Skip $KeepCount | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Write-TestResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Passed,
        [string]$Detail = ""
    )

    if ($Passed) { $tag = "PASS"; $color = "Green" }
    else         { $tag = "FAIL"; $color = "Red" }

    $msg = "[$tag] ${Id}: $Name"
    if ($Detail) { $msg += " -- $Detail" }

    [Console]::ForegroundColor = [ConsoleColor]::$color
    [Console]::WriteLine($msg)
    [Console]::ResetColor()
}

# ---------------------------------------------------------------------------
# Runtime-specific binary staging (avoid zig-out runtime mixups)
# ---------------------------------------------------------------------------

function Get-StagedGhosttyExePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][ValidateSet("winui3","win32")][string]$Runtime
    )

    return (Join-Path $RepoRoot ("tmp\bin\{0}\ghostty.exe" -f $Runtime))
}

function Build-AndStageGhosttyExe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][ValidateSet("winui3","win32")][string]$Runtime,
        [string]$Optimize = "ReleaseSafe"
    )

    $buildArgs = @("build", "-Dapp-runtime=$Runtime", "-Doptimize=$Optimize")
    if ($Runtime -eq "winui3") {
        $buildArgs += "-Drenderer=d3d11"
    }

    Push-Location $RepoRoot
    try {
        & zig @buildArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Build failed (exit code $LASTEXITCODE): zig $($buildArgs -join ' ')"
        }
    } finally {
        Pop-Location
    }

    $srcExe = Join-Path $RepoRoot "zig-out\bin\ghostty.exe"
    if (-not (Test-Path $srcExe)) {
        throw "Built binary not found: $srcExe"
    }

    $dstExe = Get-StagedGhosttyExePath -RepoRoot $RepoRoot -Runtime $Runtime
    $dstDir = Split-Path -Parent $dstExe
    New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    Copy-Item -Path $srcExe -Destination $dstExe -Force

    if ($Runtime -eq "winui3") {
        # Stage Windows App SDK bootstrap runtime next to the exe to avoid
        # immediate startup failure (WinRT bootstrap not found).
        $bootstrapName = "Microsoft.WindowsAppRuntime.Bootstrap.dll"
        $bootstrapCandidates = @(
            (Join-Path $RepoRoot $bootstrapName),
            (Join-Path $RepoRoot "scripts\$bootstrapName")
        )

        $bootstrapSource = $null
        foreach ($candidate in $bootstrapCandidates) {
            if (Test-Path $candidate) {
                $bootstrapSource = $candidate
                break
            }
        }

        if (-not $bootstrapSource) {
            throw "Required WinUI3 runtime dependency not found: $bootstrapName (checked repo root and scripts/)."
        }

        Copy-Item -Path $bootstrapSource -Destination (Join-Path $dstDir $bootstrapName) -Force
    }

    return $dstExe
}
