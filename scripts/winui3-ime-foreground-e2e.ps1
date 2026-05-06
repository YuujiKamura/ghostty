param(
    [ValidateSet("winui3")][string]$Runtime = "winui3",
    [switch]$NoBuild,
    [switch]$Strict,
    [string]$Optimize = "ReleaseSafe",
    [string]$ExePath,
    [string]$OutDir = "tmp/ime-foreground-e2e"
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\winui3-test-lib.ps1"

$repoRoot = Split-Path -Parent $PSScriptRoot
$outAbs = Join-Path $repoRoot $OutDir
$runTmpDir = Join-Path $repoRoot "tmp\ime-foreground-e2e-run"
# Resolved AFTER Start-Ghostty (per-PID file under %TEMP% — see
# tests/winui3/test-helpers.psm1 :: Get-GhosttyLogPath for the contract).
# Pre-2026-05-06 this was %USERPROFILE%\ghostty_debug.log which the binary
# never produced; downstream Wait-LogLine calls silently no-op'd.
$debugLogPath = $null

New-Item -ItemType Directory -Path $outAbs -Force | Out-Null
New-Item -ItemType Directory -Path $runTmpDir -Force | Out-Null

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class ImeForegroundWin32 {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr LoadKeyboardLayoutW(string pwszKLID, uint Flags);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr ActivateKeyboardLayout(IntPtr hkl, uint Flags);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    public const uint KEYEVENTF_KEYUP = 0x0002;
    public const uint KEYEVENTF_SCANCODE = 0x0008;
}
"@ -ErrorAction SilentlyContinue

function Assert-NoGhosttyProcess {
    $existing = @(Get-Process ghostty -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0) {
        throw "ghostty is already running; close existing instances before running this foreground IME test."
    }
}

function Reset-DebugLog {
    # Per-PID log path: a fresh file is created at every Start-Ghostty,
    # so pre-launch Reset is a no-op when $debugLogPath is unset (script
    # default). Kept for callers that pass a path post-launch.
    if ($debugLogPath -and (Test-Path $debugLogPath)) {
        Remove-Item -Path $debugLogPath -Force
    }
}

function Wait-MainWindowHandle {
    param(
        [Parameter(Mandatory)][System.Diagnostics.Process]$Process,
        [int]$TimeoutMs = 20000
    )

    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    do {
        $Process.Refresh()
        if ($Process.HasExited) {
            throw "ghostty exited before creating a main window (exit code $($Process.ExitCode))"
        }
        if ($Process.MainWindowHandle -ne 0) {
            return [IntPtr]$Process.MainWindowHandle
        }
        Start-Sleep -Milliseconds 100
    } while ((Get-Date) -lt $deadline)

    throw "main window handle was not created within ${TimeoutMs}ms"
}

function Send-ScanKey {
    param([Parameter(Mandatory)][byte]$ScanCode)

    [ImeForegroundWin32]::keybd_event(0, $ScanCode, [ImeForegroundWin32]::KEYEVENTF_SCANCODE, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 40
    [ImeForegroundWin32]::keybd_event(0, $ScanCode, [ImeForegroundWin32]::KEYEVENTF_SCANCODE -bor [ImeForegroundWin32]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 150
}

function Save-RunArtifacts {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Session,
        [Parameter(Mandatory)][string]$Stamp
    )

    $stderrCopy = Join-Path $outAbs "ime-foreground-e2e-$Stamp.stderr.log"
    $debugCopy = Join-Path $outAbs "ime-foreground-e2e-$Stamp.debug.log"

    Copy-Item -Path $Session.StderrPath -Destination $stderrCopy -Force
    if (Test-Path $debugLogPath) {
        Copy-Item -Path $debugLogPath -Destination $debugCopy -Force
    }

    return [PSCustomObject]@{
        Stderr = $stderrCopy
        Debug = $debugCopy
    }
}

Assert-NoGhosttyProcess
Reset-DebugLog
Clear-OldLogs -TmpDir $runTmpDir

function Resolve-ExePath {
    if ($ExePath) {
        return $ExePath
    }

    $directExe = Join-Path $repoRoot "zig-out-winui3\bin\ghostty.exe"
    $buildScript = Join-Path $repoRoot "build-winui3.sh"
    if (Test-Path $directExe) {
        if (-not $NoBuild -and (Test-Path $buildScript)) {
            Push-Location $repoRoot
            try {
                bash build-winui3.sh | Out-Host
                if ($LASTEXITCODE -ne 0) {
                    throw "build-winui3.sh failed with exit code $LASTEXITCODE"
                }
            } finally {
                Pop-Location
            }
        }
        return $directExe
    }

    $stagedExe = Get-StagedGhosttyExePath -RepoRoot $repoRoot -Runtime $Runtime
    if (-not $NoBuild) {
        Build-AndStageGhosttyExe -RepoRoot $repoRoot -Runtime $Runtime -Optimize $Optimize | Out-Null
    }
    return $stagedExe
}

$exePath = Resolve-ExePath
if (-not (Test-Path $exePath)) {
    throw "staged ghostty.exe not found: $exePath"
}

$workingDir = if ($exePath -like "*zig-out-winui3\bin\ghostty.exe") {
    $repoRoot
} else {
    Split-Path -Parent $exePath
}

$session = $null
$artifacts = $null
$stopCode = $null
$foregroundOk = $false

try {
    $session = Start-Ghostty -ExePath $exePath -TmpDir $runTmpDir -WorkingDirectory $workingDir
    $debugLogPath = Join-Path $env:TEMP "ghostty_debug_$($session.Process.Id).log"
    $hwnd = Wait-MainWindowHandle -Process $session.Process -TimeoutMs 20000
    Wait-LogLine -Path $debugLogPath -Pattern "step 9 OK: input HWND=" -TimeoutMs 10000 | Out-Null
    Start-Sleep -Milliseconds 500
    [Win32]::ForceForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 400
    Send-MouseClickCenter -Hwnd $hwnd
    Start-Sleep -Milliseconds 400
    $foregroundOk = ([Win32]::GetForegroundWindow() -eq $hwnd)

    $jp = [ImeForegroundWin32]::LoadKeyboardLayoutW("00000411", 0)
    if ($jp -eq [IntPtr]::Zero) {
        throw "LoadKeyboardLayoutW failed for 00000411"
    }
    [ImeForegroundWin32]::ActivateKeyboardLayout($jp, 0) | Out-Null
    Start-Sleep -Milliseconds 400

    # Hankaku/Zenkaku, then roman input for "muri", then Space / Enter, then off again.
    Send-ScanKey -ScanCode 0x29
    Send-ScanKey -ScanCode 0x32
    Send-ScanKey -ScanCode 0x16
    Send-ScanKey -ScanCode 0x13
    Send-ScanKey -ScanCode 0x17
    Send-ScanKey -ScanCode 0x39
    Send-ScanKey -ScanCode 0x1C
    Send-ScanKey -ScanCode 0x29

    Start-Sleep -Seconds 3
} finally {
    if ($session) {
        $stopCode = Stop-Ghostty -Session $session -TimeoutMs 5000
        $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $artifacts = Save-RunArtifacts -Session $session -Stamp $stamp
    }
}

if (-not $artifacts -or -not (Test-Path $artifacts.Debug)) {
    throw "missing debug log artifact"
}

$hasFocusRoute = [bool](Select-String -Path $artifacts.Debug -Pattern "ime_text_box: GotFocus" -SimpleMatch)
$compositionCount = @(
    Select-String -Path $artifacts.Debug -Pattern "ime_text_box: Composition(Started|Changed|Ended)" -ErrorAction SilentlyContinue
).Count
$commitCount = @(
    Select-String -Path $artifacts.Debug -Pattern "ime_text_box: FlushCommitted .*append_len=[1-9]" -ErrorAction SilentlyContinue
).Count

$pass = $hasFocusRoute -and ($compositionCount -gt 0) -and ($commitCount -gt 0)
$detail = "foreground=$foregroundOk composition_count=$compositionCount commit_count=$commitCount stop_code=$stopCode"

if ($pass) {
    Write-TestResult -Id "TImeForegroundE2E" -Name "WinUI3 IME foreground E2E" -Passed $true -Detail $detail
} else {
    [Console]::ForegroundColor = [ConsoleColor]::Yellow
    [Console]::WriteLine("[ADVISORY] TImeForegroundE2E: WinUI3 IME foreground E2E -- $detail")
    [Console]::ResetColor()
}

Write-Host ("  Debug log : {0}" -f $artifacts.Debug)
Write-Host ("  Stderr log: {0}" -f $artifacts.Stderr)

if ($Strict -and -not $pass) {
    exit 1
}
