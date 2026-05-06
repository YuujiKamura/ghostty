param(
    [ValidateSet("winui3")][string]$Runtime = "winui3",
    [switch]$NoBuild,
    [string]$Optimize = "ReleaseSafe",
    [string]$ExePath,
    [string]$OutDir = "tmp/ime-plumbing"
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\winui3-test-lib.ps1"

$repoRoot = Split-Path -Parent $PSScriptRoot
$outAbs = Join-Path $repoRoot $OutDir
$runTmpDir = Join-Path $repoRoot "tmp\ime-plumbing-run"
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

public static class ImePlumbingWin32 {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);

    public const uint GW_CHILD = 5;
}
"@ -ErrorAction SilentlyContinue

function Assert-NoGhosttyProcess {
    $existing = @(Get-Process ghostty -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0) {
        throw "ghostty is already running; close existing instances before running this plumbing test."
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

function Post-KeyMessage {
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd,
        [Parameter(Mandatory)][UInt16]$Vk,
        [UInt16]$Char = 0
    )

    [Win32]::PostMessageW($Hwnd, [Win32]::WM_KEYDOWN, [IntPtr]$Vk, [IntPtr]0x00010001) | Out-Null
    Start-Sleep -Milliseconds 30
    if ($Char -ne 0) {
        [Win32]::PostMessageW($Hwnd, [Win32]::WM_CHAR, [IntPtr]$Char, [IntPtr]0x00010001) | Out-Null
        Start-Sleep -Milliseconds 30
    }
    [Win32]::PostMessageW($Hwnd, [Win32]::WM_KEYUP, [IntPtr]$Vk, [IntPtr]0xC0010001) | Out-Null
    Start-Sleep -Milliseconds 80
}

function Save-RunArtifacts {
    param(
        [Parameter(Mandatory)][PSCustomObject]$Session,
        [Parameter(Mandatory)][string]$Stamp
    )

    $stderrCopy = Join-Path $outAbs "ime-plumbing-$Stamp.stderr.log"
    $debugCopy = Join-Path $outAbs "ime-plumbing-$Stamp.debug.log"

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

try {
    $session = Start-Ghostty -ExePath $exePath -TmpDir $runTmpDir -WorkingDirectory $workingDir
    $debugLogPath = Join-Path $env:TEMP "ghostty_debug_$($session.Process.Id).log"
    $hwnd = Wait-MainWindowHandle -Process $session.Process -TimeoutMs 20000
    Wait-LogLine -Path $debugLogPath -Pattern "step 9 OK: input HWND=" -TimeoutMs 10000 | Out-Null
    Start-Sleep -Milliseconds 500
    $child = [ImePlumbingWin32]::GetWindow($hwnd, [ImePlumbingWin32]::GW_CHILD)
    if ($child -eq [IntPtr]::Zero) {
        throw "WinUI3 child HWND not found"
    }

    Post-KeyMessage -Hwnd $child -Vk 0xF3
    Wait-LogLine -Path $debugLogPath -Pattern "handleKeyInput: vk=0xf3 -> focusInputOverlay" -TimeoutMs 5000 | Out-Null
    Wait-LogLine -Path $debugLogPath -Pattern "ime_text_box: GotFocus" -TimeoutMs 5000 | Out-Null

    Post-KeyMessage -Hwnd $child -Vk 0x41 -Char 0x61
    Post-KeyMessage -Hwnd $child -Vk 0x42 -Char 0x62

    Wait-LogLine -Path $debugLogPath -Pattern "ime_text_box: TextChanged .*append_len=1" -TimeoutMs 5000 | Out-Null
    Wait-LogLine -Path $debugLogPath -Pattern "ime_text_box: FlushCommitted .*append_len=1" -TimeoutMs 5000 | Out-Null

    Post-KeyMessage -Hwnd $child -Vk 0xF4
    Wait-LogLine -Path $debugLogPath -Pattern "focusKeyboardTarget: focusing SwapChainPanel" -TimeoutMs 5000 | Out-Null
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

$debugText = Get-Content -Path $artifacts.Debug
$focusRoute = [bool](Select-String -Path $artifacts.Debug -Pattern "handleKeyInput: vk=0xf3 -> focusInputOverlay" -SimpleMatch)
$imeFocus = [bool](Select-String -Path $artifacts.Debug -Pattern "ime_text_box: GotFocus" -SimpleMatch)
$flushCount = @(
    Select-String -Path $artifacts.Debug -Pattern "ime_text_box: FlushCommitted .*append_len=1" -ErrorAction SilentlyContinue
).Count
$returnFocus = [bool](Select-String -Path $artifacts.Debug -Pattern "focusKeyboardTarget: focusing SwapChainPanel" -SimpleMatch)

$pass = $focusRoute -and $imeFocus -and ($flushCount -ge 2) -and $returnFocus
$detail = "flush_append_len_1=$flushCount stop_code=$stopCode"

Write-TestResult -Id "TImePlumbing" -Name "WinUI3 IME plumbing route" -Passed $pass -Detail $detail
Write-Host ("  Debug log : {0}" -f $artifacts.Debug)
Write-Host ("  Stderr log: {0}" -f $artifacts.Stderr)

if (-not $pass) {
    exit 1
}
