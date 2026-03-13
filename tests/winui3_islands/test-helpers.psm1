# test-helpers.psm1 — Shared PowerShell module for winui3_islands GUI tests
# Usage: Import-Module .\test-helpers.psm1 -Force

Set-StrictMode -Version Latest

# ============================================================
# Win32 P/Invoke
# ============================================================
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public class Win32 {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);

    // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = -4
    public static void EnablePerMonitorDpiAwareness() {
        SetProcessDpiAwarenessContext(new IntPtr(-4));
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindowW(string className, string windowName);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hwnd);

    [DllImport("user32.dll")]
    public static extern bool IsZoomed(IntPtr hwnd);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hwnd);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool GetClientRect(IntPtr hwnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern int GetWindowLong(IntPtr hwnd, int nIndex);

    [DllImport("user32.dll")]
    public static extern uint GetDpiForWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hwnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern IntPtr GetWindow(IntPtr hwnd, uint cmd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassNameW(IntPtr hwnd, StringBuilder buf, int maxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowTextW(IntPtr hwnd, StringBuilder buf, int maxCount);

    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr parent, EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr hwnd, int x, int y, int w, int h, bool repaint);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool PostMessageW(IntPtr hwnd, uint msg, IntPtr wparam, IntPtr lparam);

    [DllImport("user32.dll")]
    public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT pt);

    [DllImport("user32.dll")]
    public static extern IntPtr SetFocus(IntPtr hwnd);

    [DllImport("imm32.dll")]
    public static extern IntPtr ImmGetContext(IntPtr hwnd);

    [DllImport("imm32.dll")]
    public static extern bool ImmReleaseContext(IntPtr hwnd, IntPtr himc);

    [DllImport("imm32.dll")]
    public static extern bool ImmGetOpenStatus(IntPtr himc);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

    public delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

    // GetWindowLong indices
    public const int GWL_STYLE   = -16;
    public const int GWL_EXSTYLE = -20;

    // GetWindow commands
    public const uint GW_CHILD    = 5;
    public const uint GW_HWNDNEXT = 2;

    // Window styles
    public const int WS_OVERLAPPEDWINDOW     = 0x00CF0000;
    public const int WS_VISIBLE              = 0x10000000;
    public const int WS_EX_NOREDIRECTIONBITMAP = 0x00200000;

    // ShowWindow commands
    public const int SW_RESTORE  = 9;
    public const int SW_MINIMIZE = 6;

    // Messages
    public const uint WM_CLOSE   = 0x0010;
    public const uint WM_KEYDOWN = 0x0100;
    public const uint WM_KEYUP   = 0x0101;
    public const uint WM_CHAR    = 0x0102;

    // SendInput constants
    public const uint INPUT_MOUSE    = 0;
    public const uint INPUT_KEYBOARD = 1;
    public const uint MOUSEEVENTF_LEFTDOWN  = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP    = 0x0004;
    public const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    public const uint MOUSEEVENTF_RIGHTUP   = 0x0010;
    public const uint MOUSEEVENTF_MOVE      = 0x0001;
    public const uint MOUSEEVENTF_ABSOLUTE  = 0x8000;

    public const uint KEYEVENTF_KEYUP       = 0x0002;
    public const uint KEYEVENTF_UNICODE     = 0x0004;

    // ----- Managed helpers (avoid marshaling headaches) -----

    public static string GetClassName(IntPtr hwnd) {
        var sb = new StringBuilder(256);
        GetClassNameW(hwnd, sb, sb.Capacity);
        return sb.ToString();
    }

    public static string GetWindowText(IntPtr hwnd) {
        var sb = new StringBuilder(256);
        GetWindowTextW(hwnd, sb, sb.Capacity);
        return sb.ToString();
    }

    /// Return all child HWNDs with their class names.
    public static List<Tuple<IntPtr, string>> GetChildWindows(IntPtr parent) {
        var list = new List<Tuple<IntPtr, string>>();
        EnumChildWindows(parent, (h, _) => {
            list.Add(Tuple.Create(h, GetClassName(h)));
            return true;
        }, IntPtr.Zero);
        return list;
    }

    /// Find a top-level window by PID.
    public static IntPtr FindWindowByPid(uint pid) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((h, _) => {
            uint wpid;
            GetWindowThreadProcessId(h, out wpid);
            if (wpid == pid && IsWindowVisible(h)) {
                found = h;
                return false; // stop enumeration
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}

[StructLayout(LayoutKind.Sequential)]
public struct RECT {
    public int Left, Top, Right, Bottom;
    public int Width  { get { return Right - Left; } }
    public int Height { get { return Bottom - Top; } }
}

[StructLayout(LayoutKind.Sequential)]
public struct POINT { public int X, Y; }

[StructLayout(LayoutKind.Explicit)]
public struct INPUT {
    [FieldOffset(0)] public uint Type;
    [FieldOffset(8)] public MOUSEINPUT    mi;
    [FieldOffset(8)] public KEYBDINPUT    ki;
}

[StructLayout(LayoutKind.Sequential)]
public struct MOUSEINPUT {
    public int    dx, dy;
    public uint   mouseData, dwFlags, time;
    public IntPtr dwExtraInfo;
}

[StructLayout(LayoutKind.Sequential)]
public struct KEYBDINPUT {
    public ushort wVk, wScan;
    public uint   dwFlags, time;
    public IntPtr dwExtraInfo;
}
"@ -ErrorAction SilentlyContinue   # Ignore if already loaded in session

# Enable per-monitor DPI awareness so GetWindowRect returns physical pixels.
[Win32]::EnablePerMonitorDpiAwareness()

# ============================================================
# Constants
# ============================================================
$script:GHOSTTY_CLASS_PRIMARY  = "GhosttyIslandWindow"
$script:GHOSTTY_WINDOW_TITLE   = "Ghostty"
$script:DEFAULT_TIMEOUT_MS     = 10000
$script:POLL_INTERVAL_MS       = 200

# ============================================================
# Process management
# ============================================================

function Start-GhosttyIslands {
    <#
    .SYNOPSIS
        Launch ghostty.exe and return the Process object.
    .PARAMETER ExePath
        Full path to ghostty.exe. Defaults to zig-out-winui3-islands\bin\ghostty.exe
        relative to the repo root.
    #>
    [CmdletBinding()]
    param(
        [string]$ExePath
    )

    if (-not $ExePath) {
        $ExePath = Join-Path $PSScriptRoot "..\..\zig-out-winui3-islands\bin\ghostty.exe"
    }
    $ExePath = (Resolve-Path $ExePath -ErrorAction Stop).Path

    if (-not (Test-Path $ExePath)) {
        throw "ghostty.exe not found at $ExePath — build first with ./build-winui3-islands.sh"
    }

    Write-Host "  Launching $ExePath ..." -ForegroundColor DarkGray
    $proc = Start-Process -FilePath $ExePath -PassThru
    return $proc
}

function Stop-GhosttyIslands {
    <#
    .SYNOPSIS
        Kill the ghostty process (and children) gracefully.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process]$Process
    )

    if (-not $Process.HasExited) {
        # Try graceful close first
        $hwnd = Find-GhosttyWindow -ProcessId $Process.Id -TimeoutMs 1000 -NoThrow
        if ($hwnd -and $hwnd -ne [IntPtr]::Zero) {
            [Win32]::PostMessageW($hwnd, [Win32]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
            $Process | Wait-Process -Timeout 5 -ErrorAction SilentlyContinue
        }
        if (-not $Process.HasExited) {
            $Process | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host "  Ghostty process stopped." -ForegroundColor DarkGray
}

# ============================================================
# Window discovery
# ============================================================

function Find-GhosttyWindow {
    <#
    .SYNOPSIS
        Find the Ghostty top-level HWND. Tries class name first, then falls back
        to searching by window title, then by PID.
    .PARAMETER ProcessId
        If specified, restrict search to this PID.
    .PARAMETER TimeoutMs
        How long to wait for the window to appear.
    .PARAMETER NoThrow
        Return $null instead of throwing on timeout.
    #>
    [CmdletBinding()]
    param(
        [uint32]$ProcessId = 0,
        [int]$TimeoutMs = $script:DEFAULT_TIMEOUT_MS,
        [switch]$NoThrow
    )

    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)

    while ([DateTime]::UtcNow -lt $deadline) {
        # Strategy 1: FindWindowW by known class name
        $hwnd = [Win32]::FindWindowW($script:GHOSTTY_CLASS_PRIMARY, $null)
        if ($hwnd -ne [IntPtr]::Zero -and [Win32]::IsWindowVisible($hwnd)) {
            if ($ProcessId -eq 0 -or (Test-WindowBelongsToPid $hwnd $ProcessId)) {
                Write-Host "  Found window via class '$script:GHOSTTY_CLASS_PRIMARY' -> 0x$($hwnd.ToString('X'))" -ForegroundColor DarkGray
                return $hwnd
            }
        }

        # Strategy 2: FindWindowW by title (class name might differ in future builds)
        $hwnd = [Win32]::FindWindowW($null, $script:GHOSTTY_WINDOW_TITLE)
        if ($hwnd -ne [IntPtr]::Zero -and [Win32]::IsWindowVisible($hwnd)) {
            if ($ProcessId -eq 0 -or (Test-WindowBelongsToPid $hwnd $ProcessId)) {
                $cls = [Win32]::GetClassName($hwnd)
                Write-Host "  Found window via title '$script:GHOSTTY_WINDOW_TITLE' (class='$cls') -> 0x$($hwnd.ToString('X'))" -ForegroundColor DarkGray
                return $hwnd
            }
        }

        # Strategy 3: Enumerate by PID (catches renamed class+title)
        if ($ProcessId -ne 0) {
            $hwnd = [Win32]::FindWindowByPid($ProcessId)
            if ($hwnd -ne [IntPtr]::Zero) {
                $cls = [Win32]::GetClassName($hwnd)
                $ttl = [Win32]::GetWindowText($hwnd)
                Write-Host "  Found window via PID $ProcessId (class='$cls', title='$ttl') -> 0x$($hwnd.ToString('X'))" -ForegroundColor DarkGray
                return $hwnd
            }
        }

        Start-Sleep -Milliseconds $script:POLL_INTERVAL_MS
    }

    if ($NoThrow) { return [IntPtr]::Zero }
    throw "Timed out waiting for Ghostty window (${TimeoutMs}ms)"
}

function Test-WindowBelongsToPid {
    [CmdletBinding()]
    param(
        [IntPtr]$Hwnd,
        [uint32]$Pid
    )
    $wpid = [uint32]0
    [Win32]::GetWindowThreadProcessId($Hwnd, [ref]$wpid) | Out-Null
    return ($wpid -eq $Pid)
}

# ============================================================
# Window inspection
# ============================================================

function Get-WindowPosition {
    <#
    .SYNOPSIS
        Return window RECT (screen coordinates).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][IntPtr]$Hwnd)
    $r = New-Object RECT
    if (-not [Win32]::GetWindowRect($Hwnd, [ref]$r)) {
        throw "GetWindowRect failed for 0x$($Hwnd.ToString('X'))"
    }
    return $r
}

function Get-ClientPosition {
    <#
    .SYNOPSIS
        Return client-area RECT.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][IntPtr]$Hwnd)
    $r = New-Object RECT
    if (-not [Win32]::GetClientRect($Hwnd, [ref]$r)) {
        throw "GetClientRect failed for 0x$($Hwnd.ToString('X'))"
    }
    return $r
}

function Get-ChildWindows {
    <#
    .SYNOPSIS
        Return list of [Tuple[IntPtr, string]] for all child windows.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][IntPtr]$Hwnd)
    return [Win32]::GetChildWindows($Hwnd)
}

function Get-ChildWindowByClass {
    <#
    .SYNOPSIS
        Return the first child HWND whose class name matches ClassName.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][string]$ClassName
    )

    foreach ($child in [Win32]::GetChildWindows($Hwnd)) {
        if ($child.Item2 -eq $ClassName) {
            return $child.Item1
        }
    }

    return [IntPtr]::Zero
}

# ============================================================
# Assertions
# ============================================================

function Test-Assert {
    <#
    .SYNOPSIS
        Assert a condition. Throws on failure (caught by runner as FAIL).
    .PARAMETER Condition
        Boolean expression result.
    .PARAMETER Message
        Description of what is being tested.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Condition) {
        Write-Host "  PASS: $Message" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: $Message" -ForegroundColor Red
        throw "Assertion failed: $Message"
    }
}

function Test-AssertEqual {
    <#
    .SYNOPSIS
        Assert two values are equal.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)]$Actual,
        [Parameter(Mandatory)][string]$Message
    )
    if ($Expected -eq $Actual) {
        Write-Host "  PASS: $Message (=$Actual)" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: $Message (expected=$Expected, actual=$Actual)" -ForegroundColor Red
        throw "Assertion failed: $Message (expected=$Expected, actual=$Actual)"
    }
}

function Test-AssertInRange {
    <#
    .SYNOPSIS
        Assert a numeric value is within [Min, Max].
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][double]$Value,
        [Parameter(Mandatory)][double]$Min,
        [Parameter(Mandatory)][double]$Max,
        [Parameter(Mandatory)][string]$Message
    )
    $ok = ($Value -ge $Min -and $Value -le $Max)
    if ($ok) {
        Write-Host "  PASS: $Message ($Value in [$Min, $Max])" -ForegroundColor Green
    } else {
        Write-Host "  FAIL: $Message ($Value not in [$Min, $Max])" -ForegroundColor Red
        throw "Assertion failed: $Message ($Value not in [$Min, $Max])"
    }
}

# ============================================================
# Input simulation
# ============================================================

function Send-MouseClick {
    <#
    .SYNOPSIS
        Click at absolute screen coordinates.
    .PARAMETER X
        Screen X.
    .PARAMETER Y
        Screen Y.
    .PARAMETER Button
        "Left" or "Right".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y,
        [string]$Button = "Left"
    )

    [Win32]::SetCursorPos($X, $Y) | Out-Null
    Start-Sleep -Milliseconds 50

    $downFlag = if ($Button -eq "Right") { [Win32]::MOUSEEVENTF_RIGHTDOWN } else { [Win32]::MOUSEEVENTF_LEFTDOWN }
    $upFlag   = if ($Button -eq "Right") { [Win32]::MOUSEEVENTF_RIGHTUP   } else { [Win32]::MOUSEEVENTF_LEFTUP   }

    $down = New-Object INPUT
    $down.Type = [Win32]::INPUT_MOUSE
    $down.mi.dwFlags = $downFlag

    $up = New-Object INPUT
    $up.Type = [Win32]::INPUT_MOUSE
    $up.mi.dwFlags = $upFlag

    [Win32]::SendInput(2, @($down, $up), [System.Runtime.InteropServices.Marshal]::SizeOf([type][INPUT])) | Out-Null
}

function Send-MouseDrag {
    <#
    .SYNOPSIS
        Drag from (X1,Y1) to (X2,Y2).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$X1,
        [Parameter(Mandatory)][int]$Y1,
        [Parameter(Mandatory)][int]$X2,
        [Parameter(Mandatory)][int]$Y2,
        [int]$Steps = 10,
        [int]$StepDelayMs = 10
    )

    [Win32]::SetCursorPos($X1, $Y1) | Out-Null
    Start-Sleep -Milliseconds 50

    # Mouse down
    $down = New-Object INPUT
    $down.Type = [Win32]::INPUT_MOUSE
    $down.mi.dwFlags = [Win32]::MOUSEEVENTF_LEFTDOWN
    [Win32]::SendInput(1, @($down), [System.Runtime.InteropServices.Marshal]::SizeOf([type][INPUT])) | Out-Null

    # Interpolate
    for ($i = 1; $i -le $Steps; $i++) {
        $t = $i / $Steps
        $cx = [int]($X1 + ($X2 - $X1) * $t)
        $cy = [int]($Y1 + ($Y2 - $Y1) * $t)
        [Win32]::SetCursorPos($cx, $cy) | Out-Null
        Start-Sleep -Milliseconds $StepDelayMs
    }

    # Mouse up
    $up = New-Object INPUT
    $up.Type = [Win32]::INPUT_MOUSE
    $up.mi.dwFlags = [Win32]::MOUSEEVENTF_LEFTUP
    [Win32]::SendInput(1, @($up), [System.Runtime.InteropServices.Marshal]::SizeOf([type][INPUT])) | Out-Null
}

function Send-KeyPress {
    <#
    .SYNOPSIS
        Send a key press via SendInput.
    .PARAMETER VirtualKey
        Virtual key code (e.g. 0x0D for Enter, 0x1B for Escape).
    .PARAMETER Char
        Alternatively, send a Unicode character.
    #>
    [CmdletBinding()]
    param(
        [ushort]$VirtualKey = 0,
        [char]$Char = [char]0
    )

    $down = New-Object INPUT
    $down.Type = [Win32]::INPUT_KEYBOARD

    $up = New-Object INPUT
    $up.Type = [Win32]::INPUT_KEYBOARD

    if ($VirtualKey -ne 0) {
        $down.ki.wVk = $VirtualKey
        $up.ki.wVk   = $VirtualKey
        $up.ki.dwFlags = [Win32]::KEYEVENTF_KEYUP
    } elseif ($Char -ne [char]0) {
        $down.ki.wScan = [ushort]$Char
        $down.ki.dwFlags = [Win32]::KEYEVENTF_UNICODE
        $up.ki.wScan   = [ushort]$Char
        $up.ki.dwFlags  = [Win32]::KEYEVENTF_UNICODE -bor [Win32]::KEYEVENTF_KEYUP
    } else {
        throw "Send-KeyPress: specify -VirtualKey or -Char"
    }

    [Win32]::SendInput(2, @($down, $up), [System.Runtime.InteropServices.Marshal]::SizeOf([type][INPUT])) | Out-Null
}

# ============================================================
# Utility
# ============================================================

function Wait-Condition {
    <#
    .SYNOPSIS
        Poll a scriptblock until it returns $true, or throw on timeout.
    .PARAMETER ScriptBlock
        The condition to evaluate. Must return $true/$false.
    .PARAMETER TimeoutMs
        Maximum wait time.
    .PARAMETER PollMs
        Interval between checks.
    .PARAMETER Description
        What we are waiting for (used in timeout error message).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [int]$TimeoutMs = $script:DEFAULT_TIMEOUT_MS,
        [int]$PollMs = $script:POLL_INTERVAL_MS,
        [string]$Description = "condition"
    )

    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (& $ScriptBlock) { return }
        Start-Sleep -Milliseconds $PollMs
    }
    throw "Timed out waiting for: $Description (${TimeoutMs}ms)"
}

function Capture-ScreenRegion {
    <#
    .SYNOPSIS
        Capture a screen region into a System.Drawing.Bitmap.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height
    )

    Add-Type -AssemblyName System.Drawing

    $bmp = New-Object System.Drawing.Bitmap($Width, $Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $graphics.CopyFromScreen($X, $Y, 0, 0, $bmp.Size)
        return $bmp
    } finally {
        $graphics.Dispose()
    }
}

function Get-BitmapSampleSignature {
    <#
    .SYNOPSIS
        Produce a compact signature of sampled bitmap pixels.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Bitmap,
        [int]$Columns = 8,
        [int]$Rows = 4
    )

    $samples = [System.Collections.Generic.List[string]]::new()
    $stepX = [Math]::Max(1, [int]($Bitmap.Width / ($Columns + 1)))
    $stepY = [Math]::Max(1, [int]($Bitmap.Height / ($Rows + 1)))

    for ($row = 1; $row -le $Rows; $row++) {
        for ($col = 1; $col -le $Columns; $col++) {
            $x = [Math]::Min($Bitmap.Width - 1, $col * $stepX)
            $y = [Math]::Min($Bitmap.Height - 1, $row * $stepY)
            $px = $Bitmap.GetPixel($x, $y)
            $samples.Add(("{0:X2}{1:X2}{2:X2}" -f $px.R, $px.G, $px.B)) | Out-Null
        }
    }

    return ($samples -join ",")
}

function Get-BitmapUniqueColorCount {
    <#
    .SYNOPSIS
        Count unique sampled colors in a bitmap.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Bitmap,
        [int]$Columns = 12,
        [int]$Rows = 6
    )

    $set = [System.Collections.Generic.HashSet[string]]::new()
    $stepX = [Math]::Max(1, [int]($Bitmap.Width / ($Columns + 1)))
    $stepY = [Math]::Max(1, [int]($Bitmap.Height / ($Rows + 1)))

    for ($row = 1; $row -le $Rows; $row++) {
        for ($col = 1; $col -le $Columns; $col++) {
            $x = [Math]::Min($Bitmap.Width - 1, $col * $stepX)
            $y = [Math]::Min($Bitmap.Height - 1, $row * $stepY)
            $px = $Bitmap.GetPixel($x, $y)
            $null = $set.Add(("{0:X2}{1:X2}{2:X2}" -f $px.R, $px.G, $px.B))
        }
    }

    return $set.Count
}

function Get-BitmapSampleDiffCount {
    <#
    .SYNOPSIS
        Compare two bitmaps via dense sampled pixels and count differing samples.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$BitmapA,
        [Parameter(Mandatory)]$BitmapB,
        [int]$Columns = 20,
        [int]$Rows = 10
    )

    if ($BitmapA.Width -ne $BitmapB.Width -or $BitmapA.Height -ne $BitmapB.Height) {
        throw "Bitmap size mismatch: $($BitmapA.Width)x$($BitmapA.Height) vs $($BitmapB.Width)x$($BitmapB.Height)"
    }

    $diffCount = 0
    $stepX = [Math]::Max(1, [int]($BitmapA.Width / ($Columns + 1)))
    $stepY = [Math]::Max(1, [int]($BitmapA.Height / ($Rows + 1)))

    for ($row = 1; $row -le $Rows; $row++) {
        for ($col = 1; $col -le $Columns; $col++) {
            $x = [Math]::Min($BitmapA.Width - 1, $col * $stepX)
            $y = [Math]::Min($BitmapA.Height - 1, $row * $stepY)
            $pxA = $BitmapA.GetPixel($x, $y)
            $pxB = $BitmapB.GetPixel($x, $y)
            if ($pxA.ToArgb() -ne $pxB.ToArgb()) {
                $diffCount++
            }
        }
    }

    return $diffCount
}

# ============================================================
# Exports
# ============================================================
Export-ModuleMember -Function @(
    'Start-GhosttyIslands'
    'Stop-GhosttyIslands'
    'Find-GhosttyWindow'
    'Get-WindowPosition'
    'Get-ClientPosition'
    'Get-ChildWindows'
    'Get-ChildWindowByClass'
    'Test-Assert'
    'Test-AssertEqual'
    'Test-AssertInRange'
    'Send-MouseClick'
    'Send-MouseDrag'
    'Send-KeyPress'
    'Wait-Condition'
    'Capture-ScreenRegion'
    'Get-BitmapSampleSignature'
    'Get-BitmapUniqueColorCount'
    'Get-BitmapSampleDiffCount'
)
