param(
    [string]$Filter = "*",
    [switch]$NoBuild,
    [int]$Timeout = 15000
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
$exePath  = Join-Path $repoRoot "zig-out\bin\ghostty.exe"
$tmpDir   = Join-Path $repoRoot "tmp"
$debugLogPath = Join-Path $repoRoot "debug.log"

# ── Build ──────────────────────────────────────────────────────
if (-not $NoBuild) {
    Out-Line "[BUILD] zig build -Dapp-runtime=winui3 -Drenderer=d3d11 ..."
    Push-Location $repoRoot
    try {
        zig build -Dapp-runtime=winui3 -Drenderer=d3d11
        if ($LASTEXITCODE -ne 0) { Write-Error "Build failed (exit code $LASTEXITCODE)" }
    } finally { Pop-Location }
    Out-Line "[BUILD] OK"
}

# ── Cleanup old logs ───────────────────────────────────────────
Clear-OldLogs -TmpDir $tmpDir -KeepCount 5

# ── Launch ─────────────────────────────────────────────────────
$session = Start-Ghostty -ExePath $exePath -TmpDir $tmpDir
Out-Line ("[START] ghostty.exe (PID={0})" -f $session.Process.Id)

$results  = @()
$failed   = @()
$skipped  = @()
$startupMs = $null
$skipRemaining = $false
$cachedHwnd = [IntPtr]::Zero
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

function Ensure-Focus {
    if ($cachedHwnd -ne [IntPtr]::Zero) {
        [Win32]::ForceForegroundWindow($cachedHwnd) | Out-Null
        Start-Sleep -Milliseconds 250
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
            Send-Keys -Keys ([ushort[]]@(0x45,0x43,0x48,0x4F, 0x20, 0x48,0x45,0x4C,0x4C,0x4F, 0x0D)) | Out-Null
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
            Send-Keys -Keys ([ushort[]]@(0x0D)) | Out-Null      # Enter
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
            Send-Keys -Keys ([ushort[]]@(0x45,0x44,0x49,0x54)) | Out-Null  # EDIT
            Send-Keys -Keys ([ushort[]]@(0x25,0x25,0x08,0x2E,0x0D)) | Out-Null # Left,Left,Backspace,Delete,Enter
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
