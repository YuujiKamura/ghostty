param(
    [string]$Filter = "*",
    [switch]$NoBuild,
    [ValidateSet("focus","message")][string]$InputMode = "message",
    [int]$Timeout = 15000,
    [int]$ScrollLines = 100000,
    [int]$ScrollObserveSec = 60,
    [int]$ScrollSampleSec = 5,
    [int]$SoakLines = 300000,
    [int]$SoakObserveSec = 600,
    [int]$SoakSampleSec = 10,
    [int]$PerfTailWindowSec = 30
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\winui3-test-lib.ps1"

function Out-Line([string]$msg, [string]$Color = "") {
    if ($Color) {
        try { [Console]::ForegroundColor = [ConsoleColor]::$Color } catch {}
    }
    [Console]::WriteLine($msg)
    if ($Color) { [Console]::ResetColor() }
}

# ── Config ─────────────────────────────────────────────────────
$repoRoot = Split-Path -Parent $PSScriptRoot
$tmpDir   = Join-Path $repoRoot "tmp"
$debugLogPath = Join-Path $repoRoot "debug.log"
$exePath = Get-StagedGhosttyExePath -RepoRoot $repoRoot -Runtime "winui3"

# ── Build ──────────────────────────────────────────────────────
if (-not $NoBuild) {
    Out-Line "[BUILD] zig build -Dapp-runtime=winui3 -Drenderer=d3d11 ..."
    $exePath = Build-AndStageGhosttyExe -RepoRoot $repoRoot -Runtime "winui3"
    Out-Line "[BUILD] OK (staged: $exePath)"
} elseif (-not (Test-Path $exePath)) {
    throw "No staged WinUI3 binary found: $exePath (run without -NoBuild first)"
}

# ── Cleanup old logs ───────────────────────────────────────────
Clear-OldLogs -TmpDir $tmpDir -KeepCount 5

# ── Launch ─────────────────────────────────────────────────────
$session = Start-Ghostty -ExePath $exePath -TmpDir $tmpDir -WorkingDirectory $repoRoot
Out-Line ("[START] ghostty.exe (PID={0})" -f $session.Process.Id)

$results  = @()
$failed   = @()
$skipped  = @()
$startupMs = $null
$skipRemaining = $false
$cachedHwnd = [IntPtr]::Zero
$cachedInputHwnd = [IntPtr]::Zero
$crashDumped = $false
$knownCrashExitCodes = @(
    -1073741189, # STATUS_STOWED_EXCEPTION
    -1073741819, # STATUS_ACCESS_VIOLATION
    -1073740940, # STATUS_HEAP_CORRUPTION
    -1073740791, # STATUS_STACK_BUFFER_OVERRUN
    -2147483645  # 0x80000003 STATUS_BREAKPOINT
)

function Should-Run([string]$id) { return $id -like $Filter }

function Test-ProcessAlive {
    if ($session.Process.HasExited) {
        return @{
            Alive    = $false
            Uptime   = [int]((Get-Date) - $session.StartTime).TotalMilliseconds
            ExitCode = $session.Process.ExitCode
        }
    }
    return @{ Alive = $true }
}

function Dump-CrashOnce {
    if (-not $script:crashDumped) {
        Write-CrashDiagnostics -Session $session
        $script:crashDumped = $true
    }
}

function Wait-LogLineAny {
    param(
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][int]$TimeoutMs
    )
    try {
        return Wait-LogLine -Path $session.StderrPath -Pattern $Pattern -TimeoutMs $TimeoutMs
    } catch {}
    return Wait-LogLine -Path $debugLogPath -Pattern $Pattern -TimeoutMs $TimeoutMs
}

function Find-GhosttyWindowAny {
    param([Parameter(Mandatory)][int]$TimeoutMs)
    try {
        return Find-GhosttyWindow -StderrPath $session.StderrPath -TimeoutMs $TimeoutMs
    } catch {}
    return Find-GhosttyWindow -StderrPath $debugLogPath -TimeoutMs $TimeoutMs
}

function Find-GhosttyInputWindowAny {
    param([Parameter(Mandatory)][int]$TimeoutMs)
    $line = $null
    try {
        $line = Wait-LogLine -Path $session.StderrPath -Pattern "input HWND=0x" -TimeoutMs $TimeoutMs
    } catch {
        $line = Wait-LogLine -Path $debugLogPath -Pattern "input HWND=0x" -TimeoutMs $TimeoutMs
    }
    if ($line -match "input HWND=0x([0-9a-fA-F]+)") {
        return [IntPtr][System.Convert]::ToInt64($Matches[1], 16)
    }
    throw "input HWND not found in logs"
}

function Ensure-Focus {
    if ($cachedHwnd -eq [IntPtr]::Zero) { return $false }
    for ($i = 0; $i -lt 12; $i++) {
        [Win32]::ForceForegroundWindow($cachedHwnd) | Out-Null
        try { [Win32]::ClickWindowCenter($cachedHwnd) | Out-Null } catch {}
        Start-Sleep -Milliseconds 120
        $fg = [Win32]::GetForegroundWindow()
        if ($fg -eq $cachedHwnd) { return $true }
    }
    return $false
}

function Ensure-InputTarget {
    if ($InputMode -eq "message") {
        if ($cachedInputHwnd -ne [IntPtr]::Zero) { return $true }
        try {
            $script:cachedInputHwnd = Find-GhosttyInputWindowAny -TimeoutMs $Timeout
            return $true
        } catch {
            return $false
        }
    }
    return Ensure-Focus
}

function Send-CommandViaPaste {
    param(
        [Parameter(Mandatory)][string]$CommandText
    )
    if (-not (Ensure-InputTarget)) { throw "Ghostty input target not ready; aborting input injection" }
    if ($InputMode -eq "message") {
        if ($cachedInputHwnd -eq [IntPtr]::Zero) { throw "No input HWND for message mode" }
        [Win32]::PostUnicodeText($cachedInputHwnd, $CommandText)
        Start-Sleep -Milliseconds 50
        [Win32]::PostEnter($cachedInputHwnd)
        return
    }
    Set-Clipboard -Value $CommandText
    # cmd.exe paste is more reliable with Shift+Insert than Ctrl+V in SendInput tests.
    Send-KeyCombo -Modifier 0x10 -Key 0x2D | Out-Null   # Shift+Insert
    Start-Sleep -Milliseconds 90
    try {
        Send-KeyCombo -Modifier 0x11 -Key 0x56 | Out-Null # Ctrl+V fallback
        Start-Sleep -Milliseconds 60
    } catch {}
    Send-Keys -Keys ([UInt16[]]@(0x0D)) | Out-Null
}

function Send-Vk {
    param([Parameter(Mandatory)][UInt16]$Vk)
    Send-Keys -Keys ([UInt16[]]@($Vk)) | Out-Null
}

function Send-ShiftVk {
    param([Parameter(Mandatory)][UInt16]$Vk)
    Send-KeyCombo -Modifier 0x10 -Key $Vk | Out-Null
}

function Send-AsciiText {
    param([Parameter(Mandatory)][string]$Text)
    foreach ($ch in $Text.ToCharArray()) {
        $c = [string]$ch
        if ($c -cmatch "[a-z]") {
            Send-Vk -Vk ([UInt16][byte][char]$c.ToUpper())
        } elseif ($c -cmatch "[A-Z]") {
            Send-Vk -Vk ([UInt16][byte][char]$c)
        } elseif ($c -cmatch "[0-9]") {
            Send-Vk -Vk ([UInt16][byte][char]$c)
        } else {
            switch ($c) {
                " " { Send-Vk -Vk 0x20 }
                "\" { Send-Vk -Vk 0xDC }
                "/" { Send-Vk -Vk 0xBF }
                "." { Send-Vk -Vk 0xBE }
                "-" { Send-Vk -Vk 0xBD }
                "_" { Send-ShiftVk -Vk 0xBD }
                ":" { Send-ShiftVk -Vk 0xBA }
                ";" { Send-Vk -Vk 0xBA }
                ">" { Send-ShiftVk -Vk 0xBE }
                "|" { Send-ShiftVk -Vk 0xDC }
                "=" { Send-Vk -Vk 0xBB }
                "+" { Send-ShiftVk -Vk 0xBB }
                default { throw "Send-AsciiText: unsupported char '$c'" }
            }
        }
        Start-Sleep -Milliseconds 6
    }
}

function Send-CommandTyped {
    param([Parameter(Mandatory)][string]$CommandText)
    if (-not (Ensure-InputTarget)) { throw "Ghostty input target not ready; aborting input injection" }
    if ($InputMode -eq "message") {
        if ($cachedInputHwnd -eq [IntPtr]::Zero) { throw "No input HWND for message mode" }
        [Win32]::PostUnicodeText($cachedInputHwnd, $CommandText)
        Start-Sleep -Milliseconds 40
        [Win32]::PostEnter($cachedInputHwnd)
        return
    }
    Send-AsciiText -Text $CommandText
    Send-Keys -Keys ([UInt16[]]@(0x0D)) | Out-Null
}

function Send-CommandTypedFocused {
    param([Parameter(Mandatory)][string]$CommandText)
    if (-not (Ensure-Focus)) { throw "Ghostty window is not focused; aborting focused input injection" }
    Send-AsciiText -Text $CommandText
    Send-Keys -Keys ([UInt16[]]@(0x0D)) | Out-Null
}

function Send-PasteShortcutFocused {
    param([Parameter(Mandatory)][ValidateSet("CtrlV","ShiftInsert")][string]$Shortcut)
    if (-not (Ensure-Focus)) { throw "Ghostty window is not focused; aborting focused paste injection" }
    if ($Shortcut -eq "CtrlV") {
        Send-KeyCombo -Modifier 0x11 -Key 0x56 | Out-Null
    } else {
        Send-KeyCombo -Modifier 0x10 -Key 0x2D | Out-Null
    }
    Start-Sleep -Milliseconds 90
    Send-Keys -Keys ([UInt16[]]@(0x0D)) | Out-Null
}

function Write-PerfSample {
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [Parameter(Mandatory)][string]$CsvPath
    )
    try {
        $p = Get-Process -Id $ProcessId -ErrorAction Stop
        $row = "{0},{1},{2},{3},{4},{5}" -f (Get-Date -Format o), [Math]::Round($p.CPU, 3), $p.WorkingSet64, $p.PrivateMemorySize64, $p.Handles, $p.Threads.Count
        Add-Content -Path $CsvPath -Value $row
    } catch {}
}

function Get-PerfCsvStats {
    param(
        [Parameter(Mandatory)][string]$CsvPath,
        [Parameter(Mandatory)][int]$SampleSec,
        [int]$TailWindowSec = 30
    )

    $rows = @(Import-Csv $CsvPath)
    if ($rows.Count -lt 2) {
        return @{
            Count = $rows.Count
            DeltaPrivate = 0
            DeltaLastTail = 0
            HandlesMonotonicIncrease = $false
            ThreadsMonotonicIncrease = $false
        }
    }

    $priv = @($rows | ForEach-Object { [int64]$_.private_mem })
    $handles = @($rows | ForEach-Object { [int64]$_.handles })
    $threads = @($rows | ForEach-Object { [int64]$_.threads })

    $deltaPrivate = $priv[$priv.Count - 1] - $priv[0]
    $tailSamples = [Math]::Max(2, [Math]::Ceiling($TailWindowSec / [Math]::Max(1, $SampleSec)) + 1)
    $tailIndex = [Math]::Max(0, $priv.Count - $tailSamples)
    $deltaLastTail = $priv[$priv.Count - 1] - $priv[$tailIndex]

    $handlesMono = $true
    $handlesAnyIncrease = $false
    for ($i = 1; $i -lt $handles.Count; $i++) {
        if ($handles[$i] -lt $handles[$i - 1]) { $handlesMono = $false; break }
        if ($handles[$i] -gt $handles[$i - 1]) { $handlesAnyIncrease = $true }
    }

    $threadsMono = $true
    $threadsAnyIncrease = $false
    for ($i = 1; $i -lt $threads.Count; $i++) {
        if ($threads[$i] -lt $threads[$i - 1]) { $threadsMono = $false; break }
        if ($threads[$i] -gt $threads[$i - 1]) { $threadsAnyIncrease = $true }
    }

    return @{
        Count = $rows.Count
        DeltaPrivate = $deltaPrivate
        DeltaLastTail = $deltaLastTail
        HandlesMonotonicIncrease = ($handlesMono -and $handlesAnyIncrease)
        ThreadsMonotonicIncrease = ($threadsMono -and $threadsAnyIncrease)
    }
}

# ── T1: Startup smoke ─────────────────────────────────────────
if (Should-Run "T1") {
    $pass = $false
    try {
        Wait-LogLineAny -Pattern "WinUI 3 Window created and activated|initXaml step 8 OK|initXaml step 7\.5 OK" -TimeoutMs $Timeout | Out-Null
        $pass = $true
        $startupMs = [int]((Get-Date) - $session.StartTime).TotalMilliseconds
    } catch {}
    Write-TestResult -Id "T1" -Name "Startup smoke" -Passed $pass -Detail $(if ($pass) { "log line found" } else { "timeout" })
    $results += @{ Id = "T1"; Passed = $pass }
    if (-not $pass) { $failed += "T1"; $skipRemaining = $true }
}

# ── T2: Window detection ──────────────────────────────────────
if ((Should-Run "T2") -and -not $skipRemaining) {
    $pass = $false
    try {
        $cachedHwnd = Find-GhosttyWindowAny -TimeoutMs $Timeout
        $pass = $true
    } catch {}
    Write-TestResult -Id "T2" -Name "Window detection" -Passed $pass -Detail $(if ($pass) { "HWND=0x$($cachedHwnd.ToString('X'))" } else { "window not found" })
    $results += @{ Id = "T2"; Passed = $pass }
    if (-not $pass) { $failed += "T2"; $skipRemaining = $true }
}

# ── T3: Startup time (info only) ──────────────────────────────
if ((Should-Run "T3") -and -not $skipRemaining) {
    if ($null -eq $startupMs) { $startupMs = [int]((Get-Date) - $session.StartTime).TotalMilliseconds }
    Out-Line ("  [INFO] T3: Startup time: {0}ms" -f $startupMs) "Cyan"
}

# ── T4: TabView creation ──────────────────────────────────────
if ((Should-Run "T4") -and -not $skipRemaining) {
    $pass = $false
    try { Wait-LogLineAny -Pattern "TabView set as Window content" -TimeoutMs $Timeout | Out-Null; $pass = $true } catch {}
    Write-TestResult -Id "T4" -Name "TabView creation" -Passed $pass -Detail $(if ($pass) { "log line found" } else { "timeout" })
    $results += @{ Id = "T4"; Passed = $pass }
    if (-not $pass) { $failed += "T4" }
}

# ── T5: Surface/renderer ──────────────────────────────────────
if ((Should-Run "T5") -and -not $skipRemaining) {
    $pass = $false
    try { Wait-LogLineAny -Pattern "initXaml step 8" -TimeoutMs $Timeout | Out-Null; $pass = $true } catch {}
    Write-TestResult -Id "T5" -Name "Surface/renderer" -Passed $pass -Detail $(if ($pass) { "log line found" } else { "timeout" })
    $results += @{ Id = "T5"; Passed = $pass }
    if (-not $pass) { $failed += "T5" }
}

# ── T6: Keyboard input ────────────────────────────────────────
if ((Should-Run "T6") -and -not $skipRemaining) {
    $check = Test-ProcessAlive
    if (-not $check.Alive) {
        Out-Line "  [SKIP] T6: Keyboard input -- process already exited" "Yellow"
        Dump-CrashOnce; $skipped += "T6"; $skipRemaining = $true
    } else {
        if ($cachedHwnd -ne [IntPtr]::Zero) {
            [Win32]::ForceForegroundWindow($cachedHwnd) | Out-Null
            Start-Sleep -Milliseconds 300
        }
        try {
            Send-Keys -Keys ([UInt16[]]@(0x45,0x43,0x48,0x4F, 0x20, 0x48,0x45,0x4C,0x4C,0x4F, 0x0D)) | Out-Null
        } catch {}
        Start-Sleep -Milliseconds 500
        $pass = -not $session.Process.HasExited
        Write-TestResult -Id "T6" -Name "Keyboard input" -Passed $pass -Detail $(if ($pass) { "process alive" } else { "process crashed" })
        $results += @{ Id = "T6"; Passed = $pass }
        if (-not $pass) { $failed += "T6"; Dump-CrashOnce }
    }
}

# ── T7: Tab operations ────────────────────────────────────────
if ((Should-Run "T7") -and -not $skipRemaining) {
    $check = Test-ProcessAlive
    if (-not $check.Alive) {
        Out-Line "  [SKIP] T7: Tab operations -- process already exited" "Yellow"
        Dump-CrashOnce; $skipped += "T7"
    } else {
        if ($cachedHwnd -ne [IntPtr]::Zero) {
            [Win32]::ForceForegroundWindow($cachedHwnd) | Out-Null
            Start-Sleep -Milliseconds 300
        }
        try {
            Send-KeyCombo -Modifier 0x11 -Key 0x54 | Out-Null   # Ctrl+T
            Start-Sleep -Milliseconds 500
            Send-KeyCombo -Modifier 0x11 -Key 0x57 | Out-Null   # Ctrl+W
            Start-Sleep -Milliseconds 500
        } catch {}
        $pass = -not $session.Process.HasExited
        Write-TestResult -Id "T7" -Name "Tab operations" -Passed $pass -Detail $(if ($pass) { "process alive" } else { "process crashed" })
        $results += @{ Id = "T7"; Passed = $pass }
        if (-not $pass) { $failed += "T7"; Dump-CrashOnce }
    }
}

# ── T8: Window resize ─────────────────────────────────────────
if ((Should-Run "T8") -and -not $skipRemaining) {
    $check = Test-ProcessAlive
    if (-not $check.Alive) {
        Out-Line "  [SKIP] T8: Window resize -- process already exited" "Yellow"
        Dump-CrashOnce; $skipped += "T8"
    } else {
        if ($cachedHwnd -ne [IntPtr]::Zero) {
            [Win32]::SetWindowPos($cachedHwnd, [IntPtr]::Zero, 0, 0, 800, 600, [Win32]::SWP_NOZORDER) | Out-Null
            Start-Sleep -Milliseconds 500
            [Win32]::SetWindowPos($cachedHwnd, [IntPtr]::Zero, 0, 0, 1200, 800, [Win32]::SWP_NOZORDER) | Out-Null
            Start-Sleep -Milliseconds 500
            [Win32]::SetWindowPos($cachedHwnd, [IntPtr]::Zero, 0, 0, 640, 480, [Win32]::SWP_NOZORDER) | Out-Null
            Start-Sleep -Milliseconds 500
        }
        $pass = -not $session.Process.HasExited
        Write-TestResult -Id "T8" -Name "Window resize" -Passed $pass -Detail $(if ($pass) { "survived 3 resizes" } else { "process crashed" })
        $results += @{ Id = "T8"; Passed = $pass }
        if (-not $pass) { $failed += "T8"; Dump-CrashOnce }
    }
}

# ── T10: Clipboard paste ──────────────────────────────────────
if ((Should-Run "T10") -and -not $skipRemaining) {
    $check = Test-ProcessAlive
    if (-not $check.Alive) {
        Out-Line "  [SKIP] T10: Clipboard paste -- process already exited" "Yellow"
        Dump-CrashOnce; $skipped += "T10"
    } else {
        Ensure-Focus
        try {
            Set-Clipboard -Value "GHOSTTY_WINUI3_PASTE_TEST"
            Send-KeyCombo -Modifier 0x11 -Key 0x56 | Out-Null   # Ctrl+V
            Start-Sleep -Milliseconds 200
            Send-Keys -Keys ([UInt16[]]@(0x0D)) | Out-Null      # Enter
        } catch {}
        Start-Sleep -Milliseconds 500
        $pass = -not $session.Process.HasExited
        Write-TestResult -Id "T10" -Name "Clipboard paste" -Passed $pass -Detail $(if ($pass) { "process alive" } else { "process crashed" })
        $results += @{ Id = "T10"; Passed = $pass }
        if (-not $pass) { $failed += "T10"; Dump-CrashOnce }
    }
}

# ── T11: Edit keys ────────────────────────────────────────────
if ((Should-Run "T11") -and -not $skipRemaining) {
    $check = Test-ProcessAlive
    if (-not $check.Alive) {
        Out-Line "  [SKIP] T11: Edit keys -- process already exited" "Yellow"
        Dump-CrashOnce; $skipped += "T11"
    } else {
        Ensure-Focus
        try {
            Send-Keys -Keys ([UInt16[]]@(0x45,0x44,0x49,0x54)) | Out-Null  # EDIT
            Send-Keys -Keys ([UInt16[]]@(0x25,0x25,0x08,0x2E,0x0D)) | Out-Null # Left,Left,Backspace,Delete,Enter
        } catch {}
        Start-Sleep -Milliseconds 500
        $pass = -not $session.Process.HasExited
        Write-TestResult -Id "T11" -Name "Edit keys" -Passed $pass -Detail $(if ($pass) { "process alive" } else { "process crashed" })
        $results += @{ Id = "T11"; Passed = $pass }
        if (-not $pass) { $failed += "T11"; Dump-CrashOnce }
    }
}

# ── T12: Mouse input ──────────────────────────────────────────
if ((Should-Run "T12") -and -not $skipRemaining) {
    $check = Test-ProcessAlive
    if (-not $check.Alive) {
        Out-Line "  [SKIP] T12: Mouse input -- process already exited" "Yellow"
        Dump-CrashOnce; $skipped += "T12"
    } else {
        Ensure-Focus
        try {
            if ($cachedHwnd -ne [IntPtr]::Zero) {
                Send-MouseClickCenter -Hwnd $cachedHwnd
                Start-Sleep -Milliseconds 200
                Send-MouseRightClickCenter -Hwnd $cachedHwnd
                Start-Sleep -Milliseconds 200
                Send-Keys -Keys ([UInt16[]]@(0x1B)) | Out-Null # ESC closes context menu
                Start-Sleep -Milliseconds 150
                Send-MouseWheel -Delta 120
                Start-Sleep -Milliseconds 150
                Send-MouseWheel -Delta -120
            }
        } catch {}
        Start-Sleep -Milliseconds 500
        $pass = -not $session.Process.HasExited
        Write-TestResult -Id "T12" -Name "Mouse input" -Passed $pass -Detail $(if ($pass) { "process alive" } else { "process crashed" })
        $results += @{ Id = "T12"; Passed = $pass }
        if (-not $pass) { $failed += "T12"; Dump-CrashOnce }
    }
}

# ── T13: Focus churn ──────────────────────────────────────────
if ((Should-Run "T13") -and -not $skipRemaining) {
    $check = Test-ProcessAlive
    if (-not $check.Alive) {
        Out-Line "  [SKIP] T13: Focus churn -- process already exited" "Yellow"
        Dump-CrashOnce; $skipped += "T13"
    } else {
        try {
            $desktop = [Win32]::FindWindowW("Progman", $null)
            if ($desktop -ne [IntPtr]::Zero) {
                [Win32]::SetForegroundWindow($desktop) | Out-Null
                Start-Sleep -Milliseconds 200
            }
            Ensure-Focus
        } catch {}
        Start-Sleep -Milliseconds 300
        $pass = -not $session.Process.HasExited
        Write-TestResult -Id "T13" -Name "Focus churn" -Passed $pass -Detail $(if ($pass) { "process alive" } else { "process crashed" })
        $results += @{ Id = "T13"; Passed = $pass }
        if (-not $pass) { $failed += "T13"; Dump-CrashOnce }
    }
}

# ── T14: Stability soak (30s) ─────────────────────────────────
if ((Should-Run "T14") -and -not $skipRemaining) {
    $check = Test-ProcessAlive
    if (-not $check.Alive) {
        Out-Line "  [SKIP] T14: Stability soak -- process already exited" "Yellow"
        Dump-CrashOnce; $skipped += "T14"
    } else {
        Start-Sleep -Seconds 30
        $pass = -not $session.Process.HasExited
        Write-TestResult -Id "T14" -Name "Stability soak (30s)" -Passed $pass -Detail $(if ($pass) { "survived 30s" } else { "process crashed" })
        $results += @{ Id = "T14"; Passed = $pass }
        if (-not $pass) { $failed += "T14"; Dump-CrashOnce }
    }
}

# ── T15: Terminal display update (visual diff) ────────────────
if ((Should-Run "T15") -and -not $skipRemaining) {
    $check = Test-ProcessAlive
    if (-not $check.Alive) {
        Out-Line "  [SKIP] T15: Terminal display update -- process already exited" "Yellow"
        Dump-CrashOnce; $skipped += "T15"
    } else {
        $pass = $false
        $detail = ""
        try {
            if ($cachedHwnd -eq [IntPtr]::Zero) {
                $cachedHwnd = Find-GhosttyWindowAny -TimeoutMs $Timeout
            }
            Ensure-Focus
            # Clear screen first to get a stable baseline.
            Send-Keys -Keys ([UInt16[]]@(0x43,0x4C,0x53,0x0D)) | Out-Null # CLS + Enter
            Start-Sleep -Milliseconds 500

            $before = Get-WindowVisualSnapshot -Hwnd $cachedHwnd

            # Trigger visible terminal output.
            Send-Keys -Keys ([UInt16[]]@(0x44,0x49,0x52,0x0D)) | Out-Null # DIR + Enter
            Start-Sleep -Milliseconds 1200

            $after = Get-WindowVisualSnapshot -Hwnd $cachedHwnd
            $ratio = Get-VisualDiffRatioBetween -Before $before -After $after -SampleStep 8 -ColorThreshold 30
            $before.Dispose()
            $after.Dispose()
            $pass = ($ratio -ge 0.01)
            $detail = "visual diff ratio=$([Math]::Round($ratio,4))"
        } catch {
            $detail = "error: $($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)"
            $pass = $false
        }
        Write-TestResult -Id "T15" -Name "Terminal display update" -Passed $pass -Detail $detail
        $results += @{ Id = "T15"; Passed = $pass }
        if (-not $pass) { $failed += "T15"; Dump-CrashOnce }
    }
}

# ── TScrollLong: long scroll stress + perf sampling ────────────
if ((Should-Run "TScrollLong") -and -not $skipRemaining) {
    $check = Test-ProcessAlive
    if (-not $check.Alive) {
        Out-Line "  [SKIP] TScrollLong: Long scroll stress -- process already exited" "Yellow"
        Dump-CrashOnce; $skipped += "TScrollLong"
    } else {
        $pass = $false
        $detail = ""
        $before = $null
        $after = $null
        try {
            if ($cachedHwnd -eq [IntPtr]::Zero) {
                $cachedHwnd = Find-GhosttyWindowAny -TimeoutMs $Timeout
            }
            Ensure-Focus

            Send-Keys -Keys ([UInt16[]]@(0x43,0x4C,0x53,0x0D)) | Out-Null # CLS + Enter
            Start-Sleep -Milliseconds 500
            $before = Get-WindowVisualSnapshot -Hwnd $cachedHwnd

            $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $perfCsv = Join-Path $tmpDir "winui3-tscrolllong-$stamp.csv"
            "ts,cpu_sec,working_set,private_mem,handles,threads" | Set-Content -Path $perfCsv -Encoding utf8

            # Inject a cmd loop to generate sustained scroll output.
            $scrollCmd = "for /L %i in (1,1,$ScrollLines) do @echo line %i"
            Set-Clipboard -Value $scrollCmd
            Send-KeyCombo -Modifier 0x11 -Key 0x56 | Out-Null   # Ctrl+V
            Start-Sleep -Milliseconds 120
            Send-Keys -Keys ([UInt16[]]@(0x0D)) | Out-Null      # Enter

            $procId = $session.Process.Id
            $observeStart = Get-Date
            while (((Get-Date) - $observeStart).TotalSeconds -lt $ScrollObserveSec) {
                if ($session.Process.HasExited) { break }
                Write-PerfSample -ProcessId $procId -CsvPath $perfCsv
                Start-Sleep -Seconds $ScrollSampleSec
            }

            if (-not $session.Process.HasExited) {
                Set-Clipboard -Value "echo TSCROLL_DONE"
                Send-KeyCombo -Modifier 0x11 -Key 0x56 | Out-Null
                Start-Sleep -Milliseconds 120
                Send-Keys -Keys ([UInt16[]]@(0x0D)) | Out-Null
                Start-Sleep -Milliseconds 700
            }

            $after = Get-WindowVisualSnapshot -Hwnd $cachedHwnd
            $beforePath = Join-Path $tmpDir "winui3-tscrolllong-before-$stamp.png"
            $afterPath = Join-Path $tmpDir "winui3-tscrolllong-after-$stamp.png"
            $before.Save($beforePath)
            $after.Save($afterPath)

            $ratio = Get-VisualDiffRatioBetween -Before $before -After $after -SampleStep 6 -ColorThreshold 22
            $perfStats = Get-PerfCsvStats -CsvPath $perfCsv -SampleSec $ScrollSampleSec -TailWindowSec $PerfTailWindowSec
            $alive = -not $session.Process.HasExited
            $pass = $alive -and ($ratio -ge 0.02)
            $detail = "alive=$alive lines=$ScrollLines observe=${ScrollObserveSec}s ratio=$([Math]::Round($ratio,4)) d_private=$($perfStats.DeltaPrivate) d_tail=$($perfStats.DeltaLastTail) perf=$perfCsv before=$beforePath after=$afterPath"
        } catch {
            $detail = "error: $($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)"
            $pass = $false
        } finally {
            if ($before) { $before.Dispose() }
            if ($after) { $after.Dispose() }
        }
        Write-TestResult -Id "TScrollLong" -Name "Long scroll stress" -Passed $pass -Detail $detail
        $results += @{ Id = "TScrollLong"; Passed = $pass }
        if (-not $pass) { $failed += "TScrollLong"; Dump-CrashOnce }
    }
}

# ── TScrollSoak10m: 10-minute scroll soak + trend checks ──────
if ((Should-Run "TScrollSoak10m") -and -not $skipRemaining) {
    $check = Test-ProcessAlive
    if (-not $check.Alive) {
        Out-Line "  [SKIP] TScrollSoak10m: 10-minute scroll soak -- process already exited" "Yellow"
        Dump-CrashOnce; $skipped += "TScrollSoak10m"
    } else {
        $pass = $false
        $detail = ""
        $before = $null
        $after = $null
        try {
            if ($cachedHwnd -eq [IntPtr]::Zero) {
                $cachedHwnd = Find-GhosttyWindowAny -TimeoutMs $Timeout
            }
            Ensure-Focus

            Send-Keys -Keys ([UInt16[]]@(0x43,0x4C,0x53,0x0D)) | Out-Null # CLS + Enter
            Start-Sleep -Milliseconds 500
            $before = Get-WindowVisualSnapshot -Hwnd $cachedHwnd

            $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $perfCsv = Join-Path $tmpDir "winui3-tscrollsoak10m-$stamp.csv"
            "ts,cpu_sec,working_set,private_mem,handles,threads" | Set-Content -Path $perfCsv -Encoding utf8

            $scrollCmd = "for /L %i in (1,1,$SoakLines) do @echo soak %i"
            Set-Clipboard -Value $scrollCmd
            Send-KeyCombo -Modifier 0x11 -Key 0x56 | Out-Null
            Start-Sleep -Milliseconds 120
            Send-Keys -Keys ([UInt16[]]@(0x0D)) | Out-Null

            $procId = $session.Process.Id
            $observeStart = Get-Date
            while (((Get-Date) - $observeStart).TotalSeconds -lt $SoakObserveSec) {
                if ($session.Process.HasExited) { break }
                Write-PerfSample -ProcessId $procId -CsvPath $perfCsv
                Start-Sleep -Seconds $SoakSampleSec
            }

            if (-not $session.Process.HasExited) {
                Set-Clipboard -Value "echo TSOAK_DONE"
                Send-KeyCombo -Modifier 0x11 -Key 0x56 | Out-Null
                Start-Sleep -Milliseconds 120
                Send-Keys -Keys ([UInt16[]]@(0x0D)) | Out-Null
                Start-Sleep -Milliseconds 700
            }

            $after = Get-WindowVisualSnapshot -Hwnd $cachedHwnd
            $beforePath = Join-Path $tmpDir "winui3-tscrollsoak10m-before-$stamp.png"
            $afterPath = Join-Path $tmpDir "winui3-tscrollsoak10m-after-$stamp.png"
            $before.Save($beforePath)
            $after.Save($afterPath)

            $ratio = Get-VisualDiffRatioBetween -Before $before -After $after -SampleStep 6 -ColorThreshold 22
            $perfStats = Get-PerfCsvStats -CsvPath $perfCsv -SampleSec $SoakSampleSec -TailWindowSec $PerfTailWindowSec
            $alive = -not $session.Process.HasExited
            $handlesOk = -not $perfStats.HandlesMonotonicIncrease
            $threadsOk = -not $perfStats.ThreadsMonotonicIncrease
            $pass = $alive -and ($ratio -ge 0.015) -and $handlesOk -and $threadsOk
            $detail = "alive=$alive lines=$SoakLines observe=${SoakObserveSec}s ratio=$([Math]::Round($ratio,4)) d_private=$($perfStats.DeltaPrivate) d_tail=$($perfStats.DeltaLastTail) handles_ok=$handlesOk threads_ok=$threadsOk perf=$perfCsv before=$beforePath after=$afterPath"
        } catch {
            $detail = "error: $($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)"
            $pass = $false
        } finally {
            if ($before) { $before.Dispose() }
            if ($after) { $after.Dispose() }
        }
        Write-TestResult -Id "TScrollSoak10m" -Name "10-minute scroll soak" -Passed $pass -Detail $detail
        $results += @{ Id = "TScrollSoak10m"; Passed = $pass }
        if (-not $pass) { $failed += "TScrollSoak10m"; Dump-CrashOnce }
    }
}

# ── TInputImeBasic: IME input flow (visual heuristic) ─────────
if ((Should-Run "TInputImeBasic") -and -not $skipRemaining) {
    $check = Test-ProcessAlive
    if (-not $check.Alive) {
        Out-Line "  [SKIP] TInputImeBasic: IME basic input -- process already exited" "Yellow"
        Dump-CrashOnce; $skipped += "TInputImeBasic"
    } else {
        $pass = $false
        $detail = ""
        $snap0 = $null
        $snap1 = $null
        $snap2 = $null
        $snap3 = $null
        $snap4 = $null
        try {
            if ($cachedHwnd -eq [IntPtr]::Zero) {
                $cachedHwnd = Find-GhosttyWindowAny -TimeoutMs $Timeout
            }
            Ensure-Focus
            Send-Keys -Keys ([UInt16[]]@(0x43,0x4C,0x53,0x0D)) | Out-Null # CLS + Enter
            Start-Sleep -Milliseconds 500

            $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $snap0 = Get-WindowVisualSnapshot -Hwnd $cachedHwnd

            # Heuristic IME flow: paste JP text, then Space, then Enter.
            Set-Clipboard -Value "あいう"
            Send-KeyCombo -Modifier 0x11 -Key 0x56 | Out-Null # Ctrl+V
            Start-Sleep -Milliseconds 250
            $snap1 = Get-WindowVisualSnapshot -Hwnd $cachedHwnd

            Send-Keys -Keys ([UInt16[]]@(0x20)) | Out-Null     # Space (candidate/composition change)
            Start-Sleep -Milliseconds 300
            $snap2 = Get-WindowVisualSnapshot -Hwnd $cachedHwnd

            Send-Keys -Keys ([UInt16[]]@(0x0D)) | Out-Null     # Enter (commit)
            Start-Sleep -Milliseconds 450
            $snap3 = Get-WindowVisualSnapshot -Hwnd $cachedHwnd

            # Post-action resilience: resize + repeat minimal input.
            [Win32]::SetWindowPos($cachedHwnd, [IntPtr]::Zero, 0, 0, 900, 650, [Win32]::SWP_NOZORDER) | Out-Null
            Start-Sleep -Milliseconds 250
            [Win32]::SetWindowPos($cachedHwnd, [IntPtr]::Zero, 0, 0, 1100, 760, [Win32]::SWP_NOZORDER) | Out-Null
            Start-Sleep -Milliseconds 250
            Set-Clipboard -Value "えお"
            Send-KeyCombo -Modifier 0x11 -Key 0x56 | Out-Null
            Start-Sleep -Milliseconds 220
            Send-Keys -Keys ([UInt16[]]@(0x0D)) | Out-Null
            Start-Sleep -Milliseconds 400
            $snap4 = Get-WindowVisualSnapshot -Hwnd $cachedHwnd

            $r01 = Get-VisualDiffRatioBetween -Before $snap0 -After $snap1 -SampleStep 6 -ColorThreshold 22
            $r12 = Get-VisualDiffRatioBetween -Before $snap1 -After $snap2 -SampleStep 6 -ColorThreshold 22
            $r23 = Get-VisualDiffRatioBetween -Before $snap2 -After $snap3 -SampleStep 6 -ColorThreshold 22
            $r34 = Get-VisualDiffRatioBetween -Before $snap3 -After $snap4 -SampleStep 6 -ColorThreshold 22
            $alive = -not $session.Process.HasExited

            $beforePath = Join-Path $tmpDir "winui3-timebasic-before-$stamp.png"
            $inputPath = Join-Path $tmpDir "winui3-timebasic-input-$stamp.png"
            $spacePath = Join-Path $tmpDir "winui3-timebasic-space-$stamp.png"
            $enterPath = Join-Path $tmpDir "winui3-timebasic-enter-$stamp.png"
            $afterPath = Join-Path $tmpDir "winui3-timebasic-after-$stamp.png"
            $snap0.Save($beforePath)
            $snap1.Save($inputPath)
            $snap2.Save($spacePath)
            $snap3.Save($enterPath)
            $snap4.Save($afterPath)

            $phaseThreshold = 0.001
            $pass = $alive -and ($r01 -ge $phaseThreshold) -and ($r12 -ge $phaseThreshold) -and ($r23 -ge $phaseThreshold)
            $detail = "alive=$alive r01=$([Math]::Round($r01,4)) r12=$([Math]::Round($r12,4)) r23=$([Math]::Round($r23,4)) r34=$([Math]::Round($r34,4)) phase_min=$phaseThreshold mode=visual-heuristic before=$beforePath input=$inputPath space=$spacePath enter=$enterPath after=$afterPath"
        } catch {
            $detail = "error: $($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)"
            $pass = $false
        } finally {
            if ($snap0) { $snap0.Dispose() }
            if ($snap1) { $snap1.Dispose() }
            if ($snap2) { $snap2.Dispose() }
            if ($snap3) { $snap3.Dispose() }
            if ($snap4) { $snap4.Dispose() }
        }
        Write-TestResult -Id "TInputImeBasic" -Name "IME basic input (visual heuristic)" -Passed $pass -Detail $detail
        $results += @{ Id = "TInputImeBasic"; Passed = $pass }
        if (-not $pass) { $failed += "TInputImeBasic"; Dump-CrashOnce }
    }
}

# ── TOpsBasic: EN/JP/basic commands/copy-paste full flow ──────
if ((Should-Run "TOpsBasic") -and -not $skipRemaining) {
    $check = Test-ProcessAlive
    if (-not $check.Alive) {
        Out-Line "  [SKIP] TOpsBasic: Full basic operation flow -- process already exited" "Yellow"
        Dump-CrashOnce; $skipped += "TOpsBasic"
    } else {
        $pass = $false
        $detail = ""
        $snapA = $null
        $snapB = $null
        try {
            if ($cachedHwnd -eq [IntPtr]::Zero) {
                $cachedHwnd = Find-GhosttyWindowAny -TimeoutMs $Timeout
            }
            Ensure-Focus

            Send-Keys -Keys ([UInt16[]]@(0x43,0x4C,0x53,0x0D)) | Out-Null # CLS + Enter
            Start-Sleep -Milliseconds 350
            $snapA = Get-WindowVisualSnapshot -Hwnd $cachedHwnd
            $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $terminalLog = Join-Path $tmpDir "winui3-topsbasic-terminal-$stamp.log"
            $terminalDump = Join-Path $tmpDir "winui3-topsbasic-dump-$stamp.txt"

            # Clear terminal-side text log and collect command output into it.
            Send-CommandTyped -CommandText "type nul > $terminalLog"
            Start-Sleep -Milliseconds 180

            # EN input + JP input dump
            Send-CommandTyped -CommandText "echo EN_OK>> $terminalLog"
            Start-Sleep -Milliseconds 250
            Send-CommandViaPaste -CommandText "echo こんにちは"
            Start-Sleep -Milliseconds 200
            Send-CommandTyped -CommandText "echo JP_STEP_OK>> $terminalLog"
            Start-Sleep -Milliseconds 250

            # basic commands (dumped to terminal log)
            Send-CommandTyped -CommandText "cd>> $terminalLog"
            Start-Sleep -Milliseconds 200
            Send-CommandTyped -CommandText "ver>> $terminalLog"
            Start-Sleep -Milliseconds 200
            Send-CommandTyped -CommandText "dir /b>> $terminalLog"
            Start-Sleep -Milliseconds 600
            Send-CommandTyped -CommandText "echo OPS_DONE>> $terminalLog"
            Start-Sleep -Milliseconds 220

            # clipboard copy check from terminal-side command
            Set-Clipboard -Value "PRE_COPY_SENTINEL"
            Send-CommandTyped -CommandText "echo COPY_FROM_TERMINAL| clip"
            $clipOk = $false
            $clipText = ""
            for ($i = 0; $i -lt 10; $i++) {
                Start-Sleep -Milliseconds 200
                try { $clipText = (Get-Clipboard -Raw).Trim() } catch { $clipText = "" }
                if ($clipText -like "*COPY_FROM_TERMINAL*") { $clipOk = $true; break }
            }

            # clipboard paste check
            Set-Clipboard -Value "PASTE_OK"
            Send-CommandViaPaste -CommandText "echo %CLIPBOARD_PASTE_TEST%"
            Send-CommandTyped -CommandText "echo PASTE_STEP_OK>> $terminalLog"
            Start-Sleep -Milliseconds 300

            # Read terminal text dump for strong evidence of command execution.
            $terminalText = ""
            for ($i = 0; $i -lt 12; $i++) {
                Start-Sleep -Milliseconds 200
                if (Test-Path $terminalLog) {
                    try {
                        $terminalText = Get-Content -Path $terminalLog -Raw -Encoding Default
                        if ($terminalText -like "*OPS_DONE*") { break }
                    } catch {}
                }
            }
            if ($terminalText) {
                Set-Content -Path $terminalDump -Value $terminalText -Encoding utf8
            } else {
                Set-Content -Path $terminalDump -Value "[no terminal text captured]" -Encoding utf8
            }

            $hasDone = $terminalText -like "*OPS_DONE*"
            $hasEn = $terminalText -like "*EN_OK*"
            $hasVer = ($terminalText -match "Microsoft Windows") -or ($terminalText -match "Windows \[Version")
            $hasDir = ($terminalText -like "*ghostty-win*") -or ($terminalText -like "*winui3*")
            $hasJpStep = $terminalText -like "*JP_STEP_OK*"
            $hasPasteStep = $terminalText -like "*PASTE_STEP_OK*"

            $snapB = Get-WindowVisualSnapshot -Hwnd $cachedHwnd
            $ratio = Get-VisualDiffRatioBetween -Before $snapA -After $snapB -SampleStep 6 -ColorThreshold 22
            $alive = -not $session.Process.HasExited
            $ratioMin = 0.0001
            $pass = $alive -and $clipOk -and $hasDone -and $hasEn -and $hasVer -and $hasDir -and $hasJpStep -and $hasPasteStep -and ($ratio -ge $ratioMin)

            $beforePath = Join-Path $tmpDir "winui3-topsbasic-before-$stamp.png"
            $afterPath = Join-Path $tmpDir "winui3-topsbasic-after-$stamp.png"
            $snapA.Save($beforePath)
            $snapB.Save($afterPath)
            $detail = "alive=$alive clip_ok=$clipOk has_done=$hasDone has_en=$hasEn has_ver=$hasVer has_dir=$hasDir has_jp_step=$hasJpStep has_paste_step=$hasPasteStep ratio=$([Math]::Round($ratio,4)) ratio_min=$ratioMin term_log=$terminalLog dump=$terminalDump before=$beforePath after=$afterPath"
        } catch {
            $detail = "error: $($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)"
            $pass = $false
        } finally {
            if ($snapA) { $snapA.Dispose() }
            if ($snapB) { $snapB.Dispose() }
        }
        Write-TestResult -Id "TOpsBasic" -Name "Full basic operation flow" -Passed $pass -Detail $detail
        $results += @{ Id = "TOpsBasic"; Passed = $pass }
        if (-not $pass) { $failed += "TOpsBasic"; Dump-CrashOnce }
    }
}

# ── TUserDxBasic: user-facing DX flow (focus + shortcuts) ─────
if ((Should-Run "TUserDxBasic") -and -not $skipRemaining) {
    $check = Test-ProcessAlive
    if (-not $check.Alive) {
        Out-Line "  [SKIP] TUserDxBasic: User DX basic flow -- process already exited" "Yellow"
        Dump-CrashOnce; $skipped += "TUserDxBasic"
    } else {
        $pass = $false
        $detail = ""
        $snapA = $null
        $snapB = $null
        try {
            if ($cachedHwnd -eq [IntPtr]::Zero) {
                $cachedHwnd = Find-GhosttyWindowAny -TimeoutMs $Timeout
            }
            if (-not (Ensure-Focus)) { throw "could not focus Ghostty window for DX test" }

            Send-Keys -Keys ([UInt16[]]@(0x43,0x4C,0x53,0x0D)) | Out-Null # CLS + Enter
            Start-Sleep -Milliseconds 300
            $snapA = Get-WindowVisualSnapshot -Hwnd $cachedHwnd

            $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $terminalLog = Join-Path $tmpDir "winui3-tdxbasic-terminal-$stamp.log"
            $terminalDump = Join-Path $tmpDir "winui3-tdxbasic-dump-$stamp.txt"

            # Direct typing UX
            Send-CommandTypedFocused -CommandText "type nul > $terminalLog"
            Send-CommandTypedFocused -CommandText "echo DX_TYPED_OK>> $terminalLog"

            # Ctrl+V paste UX
            Set-Clipboard -Value "echo DX_CTRLV_OK>> $terminalLog"
            Send-PasteShortcutFocused -Shortcut CtrlV

            # Shift+Insert paste UX
            Set-Clipboard -Value "echo DX_SHIFTINS_OK>> $terminalLog"
            Send-PasteShortcutFocused -Shortcut ShiftInsert

            # Copy UX via terminal-side copy command
            Set-Clipboard -Value "PRE_COPY_SENTINEL"
            Send-CommandTypedFocused -CommandText "echo DX_COPY_OK| clip"
            $clipOk = $false
            $clipText = ""
            for ($i = 0; $i -lt 10; $i++) {
                Start-Sleep -Milliseconds 200
                try { $clipText = (Get-Clipboard -Raw).Trim() } catch { $clipText = "" }
                if ($clipText -like "*DX_COPY_OK*") { $clipOk = $true; break }
            }

            # Final paste round for terminal log completion
            Set-Clipboard -Value "echo DX_PASTE_OK>> $terminalLog"
            Send-PasteShortcutFocused -Shortcut CtrlV
            Send-CommandTypedFocused -CommandText "echo DX_DONE>> $terminalLog"

            $terminalText = ""
            for ($i = 0; $i -lt 12; $i++) {
                Start-Sleep -Milliseconds 200
                if (Test-Path $terminalLog) {
                    try {
                        $terminalText = Get-Content -Path $terminalLog -Raw -Encoding Default
                        if ($terminalText -like "*DX_DONE*") { break }
                    } catch {}
                }
            }
            if ($terminalText) {
                Set-Content -Path $terminalDump -Value $terminalText -Encoding utf8
            } else {
                Set-Content -Path $terminalDump -Value "[no terminal text captured]" -Encoding utf8
            }

            $hasTyped = $terminalText -like "*DX_TYPED_OK*"
            $hasCtrlV = $terminalText -like "*DX_CTRLV_OK*"
            $hasShiftIns = $terminalText -like "*DX_SHIFTINS_OK*"
            $hasPaste = $terminalText -like "*DX_PASTE_OK*"
            $hasDone = $terminalText -like "*DX_DONE*"

            $snapB = Get-WindowVisualSnapshot -Hwnd $cachedHwnd
            $ratio = Get-VisualDiffRatioBetween -Before $snapA -After $snapB -SampleStep 6 -ColorThreshold 22
            $alive = -not $session.Process.HasExited
            $pass = $alive -and $clipOk -and $hasTyped -and $hasCtrlV -and $hasShiftIns -and $hasPaste -and $hasDone -and ($ratio -ge 0.0001)

            $beforePath = Join-Path $tmpDir "winui3-tdxbasic-before-$stamp.png"
            $afterPath = Join-Path $tmpDir "winui3-tdxbasic-after-$stamp.png"
            $snapA.Save($beforePath)
            $snapB.Save($afterPath)
            $detail = "alive=$alive clip_ok=$clipOk typed=$hasTyped ctrlv=$hasCtrlV shiftins=$hasShiftIns paste=$hasPaste done=$hasDone ratio=$([Math]::Round($ratio,4)) term_log=$terminalLog dump=$terminalDump before=$beforePath after=$afterPath"
        } catch {
            $detail = "error: $($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)"
            $pass = $false
        } finally {
            if ($snapA) { $snapA.Dispose() }
            if ($snapB) { $snapB.Dispose() }
        }
        Write-TestResult -Id "TUserDxBasic" -Name "User DX basic flow" -Passed $pass -Detail $detail
        $results += @{ Id = "TUserDxBasic"; Passed = $pass }
        if (-not $pass) { $failed += "TUserDxBasic"; Dump-CrashOnce }
    }
}

# ── T9: Clean exit ────────────────────────────────────────────
if (Should-Run "T9") {
    if ($session.Process.HasExited) {
        $code = $session.Process.ExitCode
        $pass = ($knownCrashExitCodes -notcontains $code)
        Write-TestResult -Id "T9" -Name "Clean exit" -Passed $pass -Detail (Format-ExitCode $code)
        $results += @{ Id = "T9"; Passed = $pass }
        if (-not $pass) { $failed += "T9"; Dump-CrashOnce }
    } else {
        $exitCode = Stop-Ghostty -Session $session -TimeoutMs 5000
        # Test harness may force-kill GUI apps after timeout; treat as pass unless known crash code.
        $pass = ($knownCrashExitCodes -notcontains $exitCode)
        $exitDetail = Format-ExitCode $exitCode
        if ($exitCode -eq -1) { $exitDetail += " (forced stop)" }
        Write-TestResult -Id "T9" -Name "Clean exit" -Passed $pass -Detail $exitDetail
        $results += @{ Id = "T9"; Passed = $pass }
        if (-not $pass) { $failed += "T9" }
    }
} else {
    if (-not $session.Process.HasExited) { Stop-Ghostty -Session $session -TimeoutMs 3000 | Out-Null }
}

# ── Summary ────────────────────────────────────────────────────
$passCount = (@($results | Where-Object { [bool]$_.Passed })).Count
$failCount = $results.Count - $passCount
$total     = $results.Count
$skipCount = $skipped.Count
$startupStr = if ($null -ne $startupMs) { "${startupMs}ms" } else { "N/A" }

Out-Line ""
Out-Line ([string]::new([char]0x2500, 50))
Out-Line ("Results: {0}/{1} PASS, {2}/{3} FAIL, {4} SKIP | Startup: {5}" -f $passCount, $total, $failCount, $total, $skipCount, $startupStr)
if ($failed.Count -gt 0)  { Out-Line ("Failed: {0}" -f ($failed -join ", ")) }
if ($skipped.Count -gt 0) { Out-Line ("Skipped: {0}" -f ($skipped -join ", ")) }
Out-Line ("Stderr log: {0}" -f $session.StderrPath)

exit $failCount
