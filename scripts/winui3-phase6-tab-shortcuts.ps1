param(
    [switch]$NoBuild,
    [string]$Optimize = "ReleaseSafe",
    [string]$ExePath,
    [string]$OutDir = "tmp/phase6/tab-shortcuts"
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\winui3-phase6-lib.ps1"

$repoRoot = Get-Phase6RepoRoot
$outAbs = Get-Phase6OutputDir -RepoRoot $repoRoot -OutDir $OutDir
$exeResolved = Resolve-Phase6ExePath -RepoRoot $repoRoot -ExePath $ExePath -Optimize $Optimize -NoBuild:$NoBuild

$session = $null
$artifacts = $null
$focusOk = $false
$aliveAfterClose = $false
$failure = $null
$ctrlShiftTOk = $false
$ctrlShiftWOk = $false
$ctrlShiftTError = ""
$ctrlShiftWError = ""
$newTabMarker = "PHASE6_SHORTCUT_NEW_TAB_OK"
$closeTabMarker = "PHASE6_SHORTCUT_CLOSE_TAB_OK"

try {
    $session = Start-Phase6Session -RepoRoot $repoRoot -ExePath $exeResolved -OutDir $outAbs -Env (New-Phase6Env)
    Wait-Phase6PromptReady -Control $session.Control -TimeoutMs 20000 | Out-Null

    $focusOk = Ensure-Phase6Foreground -Session $session -TimeoutMs 6000
    if (-not $focusOk) {
        throw "ghostty window did not reach foreground before Ctrl+Shift+T"
    }

    Send-KeyChord -Modifiers @(0x11, 0x10) -Key 0x54 | Out-Null
    try {
        Wait-Phase6TabCount -Control $session.Control -Expected 2 -TimeoutMs 12000 | Out-Null
        Wait-Phase6ActiveTab -Control $session.Control -Expected 1 -TimeoutMs 12000 | Out-Null
        Invoke-Phase6ShellCommand -Control $session.Control -Command ("echo {0}" -f $newTabMarker) | Out-Null
        Wait-Phase6TailContains -Control $session.Control -Text $newTabMarker -TimeoutMs 12000 | Out-Null
        $ctrlShiftTOk = $true
    } catch {
        $ctrlShiftTError = $_.Exception.Message
    }

    if ($ctrlShiftTOk) {
        $focusOk = Ensure-Phase6Foreground -Session $session -TimeoutMs 6000
        if (-not $focusOk) {
            throw "ghostty window did not reach foreground before Ctrl+Shift+W"
        }

        Send-KeyChord -Modifiers @(0x11, 0x10) -Key 0x57 | Out-Null
        try {
            Wait-Phase6TabCount -Control $session.Control -Expected 1 -TimeoutMs 12000 | Out-Null
            Wait-Phase6ActiveTab -Control $session.Control -Expected 0 -TimeoutMs 12000 | Out-Null
            Invoke-Phase6ShellCommand -Control $session.Control -Command ("echo {0}" -f $closeTabMarker) | Out-Null
            Wait-Phase6TailContains -Control $session.Control -Text $closeTabMarker -TimeoutMs 12000 | Out-Null
            $ctrlShiftWOk = $true
        } catch {
            $ctrlShiftWError = $_.Exception.Message
        }
    }

    $aliveAfterClose = -not $session.Process.HasExited
} catch {
    $failure = $_.Exception.Message
} finally {
    if ($session) {
        $artifacts = Stop-Phase6Session -Session $session -ArtifactPrefix "tab-shortcuts"
    }
}

$pass = ($failure -eq $null) -and $focusOk -and $aliveAfterClose -and $ctrlShiftTOk -and $ctrlShiftWOk -and ($artifacts.ExitCode -eq 0)
$detail = "error=$failure focus=$focusOk ctrl_shift_t=$ctrlShiftTOk ctrl_shift_t_error=$ctrlShiftTError ctrl_shift_w=$ctrlShiftWOk ctrl_shift_w_error=$ctrlShiftWError alive_after_ctrl_shift_w=$aliveAfterClose exit=$(Format-ExitCode $artifacts.ExitCode)"

Write-TestResult -Id "P6-SHORTCUTS" -Name "Phase 6 Ctrl+Shift+T / Ctrl+Shift+W tab shortcuts" -Passed $pass -Detail $detail
Write-Host ("  Debug log : {0}" -f $artifacts.DebugLog)
Write-Host ("  Stderr log: {0}" -f $artifacts.StderrLog)

if (-not $pass) {
    exit 1
}
