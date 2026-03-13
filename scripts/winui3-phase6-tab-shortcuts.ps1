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
$ctrlTOk = $false
$ctrlWOk = $false
$ctrlTError = ""
$ctrlWError = ""

try {
    $session = Start-Phase6Session -RepoRoot $repoRoot -ExePath $exeResolved -OutDir $outAbs -Env (New-Phase6Env)
    Wait-Phase6PromptReady -Control $session.Control -TimeoutMs 20000 | Out-Null

    $focusOk = Ensure-Phase6Foreground -Session $session -TimeoutMs 6000
    if (-not $focusOk) {
        throw "ghostty window did not reach foreground before Ctrl+T"
    }

    Send-KeyCombo -Modifier 0x11 -Key 0x54 | Out-Null
    try {
        Wait-Phase6TabCount -Control $session.Control -Expected 2 -TimeoutMs 12000 | Out-Null
        Wait-Phase6ActiveTab -Control $session.Control -Expected 1 -TimeoutMs 12000 | Out-Null
        Wait-Phase6PromptReady -Control $session.Control -TimeoutMs 12000 | Out-Null
        $ctrlTOk = $true
    } catch {
        $ctrlTError = $_.Exception.Message
    }

    if ($ctrlTOk) {
        $focusOk = Ensure-Phase6Foreground -Session $session -TimeoutMs 6000
        if (-not $focusOk) {
            throw "ghostty window did not reach foreground before Ctrl+W"
        }

        Send-KeyCombo -Modifier 0x11 -Key 0x57 | Out-Null
        try {
            Wait-Phase6TabCount -Control $session.Control -Expected 1 -TimeoutMs 12000 | Out-Null
            Wait-Phase6ActiveTab -Control $session.Control -Expected 0 -TimeoutMs 12000 | Out-Null
            Wait-Phase6PromptReady -Control $session.Control -TimeoutMs 12000 | Out-Null
            $ctrlWOk = $true
        } catch {
            $ctrlWError = $_.Exception.Message
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

$pass = ($failure -eq $null) -and $focusOk -and $aliveAfterClose -and $ctrlTOk -and $ctrlWOk -and ($artifacts.ExitCode -eq 0)
$detail = "error=$failure focus=$focusOk ctrl_t=$ctrlTOk ctrl_t_error=$ctrlTError ctrl_w=$ctrlWOk ctrl_w_error=$ctrlWError alive_after_ctrlw=$aliveAfterClose exit=$(Format-ExitCode $artifacts.ExitCode)"

Write-TestResult -Id "P6-SHORTCUTS" -Name "Phase 6 Ctrl+T / Ctrl+W tab shortcuts" -Passed $pass -Detail $detail
Write-Host ("  Debug log : {0}" -f $artifacts.DebugLog)
Write-Host ("  Stderr log: {0}" -f $artifacts.StderrLog)

if (-not $pass) {
    exit 1
}
