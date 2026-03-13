param(
    [switch]$NoBuild,
    [string]$Optimize = "ReleaseSafe",
    [string]$ExePath,
    [string]$OutDir = "tmp/phase6/ime-japanese"
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\winui3-phase6-lib.ps1"

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class Phase6ImeNative {
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

function Send-Phase6ScanKey {
    param([Parameter(Mandatory)][byte]$ScanCode)

    [Phase6ImeNative]::keybd_event(0, $ScanCode, [Phase6ImeNative]::KEYEVENTF_SCANCODE, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 40
    [Phase6ImeNative]::keybd_event(
        0,
        $ScanCode,
        [Phase6ImeNative]::KEYEVENTF_SCANCODE -bor [Phase6ImeNative]::KEYEVENTF_KEYUP,
        [UIntPtr]::Zero
    )
    Start-Sleep -Milliseconds 150
}

$repoRoot = Get-Phase6RepoRoot
$outAbs = Get-Phase6OutputDir -RepoRoot $repoRoot -OutDir $OutDir
$exeResolved = Resolve-Phase6ExePath -RepoRoot $repoRoot -ExePath $ExePath -Optimize $Optimize -NoBuild:$NoBuild

$session = $null
$artifacts = $null
$foregroundOk = $false
$failure = $null

try {
    $session = Start-Phase6Session -RepoRoot $repoRoot -ExePath $exeResolved -OutDir $outAbs -Env (New-Phase6Env)
    Wait-Phase6PromptReady -Control $session.Control -TimeoutMs 20000 | Out-Null
    Wait-Phase6LogLineAny -Session $session -Pattern "step 9 OK: input HWND=" -TimeoutMs 10000 | Out-Null
    $foregroundOk = Ensure-Phase6Foreground -Session $session -TimeoutMs 6000
    if (-not $foregroundOk) {
        throw "ghostty window did not reach foreground"
    }

    $jp = [Phase6ImeNative]::LoadKeyboardLayoutW("00000411", 0)
    if ($jp -eq [IntPtr]::Zero) {
        throw "LoadKeyboardLayoutW failed for 00000411"
    }
    [Phase6ImeNative]::ActivateKeyboardLayout($jp, 0) | Out-Null
    Start-Sleep -Milliseconds 400

    Send-Phase6ScanKey -ScanCode 0x29
    Send-Phase6ScanKey -ScanCode 0x32
    Send-Phase6ScanKey -ScanCode 0x16
    Send-Phase6ScanKey -ScanCode 0x13
    Send-Phase6ScanKey -ScanCode 0x17
    Send-Phase6ScanKey -ScanCode 0x39
    Send-Phase6ScanKey -ScanCode 0x1C
    Send-Phase6ScanKey -ScanCode 0x29

    Start-Sleep -Seconds 2
} catch {
    $failure = $_.Exception.Message
} finally {
    if ($session) {
        $artifacts = Stop-Phase6Session -Session $session -ArtifactPrefix "ime-japanese"
    }
}

$debugText = if ($artifacts -and (Test-Path $artifacts.DebugLog)) {
    Get-Content -Path $artifacts.DebugLog -Raw -ErrorAction SilentlyContinue
} else {
    ""
}

$hasFocusRoute = $debugText.Contains("ime_text_box: GotFocus")
$compositionCount = ([regex]::Matches($debugText, "ime_text_box: Composition(Started|Changed|Ended)")).Count
$commitCount = ([regex]::Matches($debugText, "ime_text_box: FlushCommitted .*append_len=[1-9]")).Count
$pass = ($failure -eq $null) -and $foregroundOk -and $hasFocusRoute -and ($compositionCount -gt 0) -and ($commitCount -gt 0) -and ($artifacts.ExitCode -eq 0)
$detail = "error=$failure foreground=$foregroundOk focus_route=$hasFocusRoute composition_count=$compositionCount commit_count=$commitCount exit=$(Format-ExitCode $artifacts.ExitCode)"

Write-TestResult -Id "P6-IME" -Name "Phase 6 IME Japanese input" -Passed $pass -Detail $detail
Write-Host ("  Debug log : {0}" -f $artifacts.DebugLog)
Write-Host ("  Stderr log: {0}" -f $artifacts.StderrLog)

if (-not $pass) {
    exit 1
}
