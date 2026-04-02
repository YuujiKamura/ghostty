param(
    [switch]$NoBuild,
    [string]$Optimize = "ReleaseSafe",
    [string]$ExePath,
    [string]$OutDir = "tmp/phase6/tab-title-follow"
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\winui3-phase6-lib.ps1"

function New-Phase6TitleCommand {
    param([Parameter(Mandatory)][string]$Title)

    return ("title {0}" -f $Title)
}

$repoRoot = Get-Phase6RepoRoot
$outAbs = Get-Phase6OutputDir -RepoRoot $repoRoot -OutDir $OutDir
$exeResolved = Resolve-Phase6ExePath -RepoRoot $repoRoot -ExePath $ExePath -Optimize $Optimize -NoBuild:$NoBuild

$session = $null
$artifacts = $null
$titleA = "PHASE6_TITLE_A"
$titleB = "PHASE6_TITLE_B"
$tabsSnapshot = $null
$stateTitleAOk = $false
$stateTitleBOk = $false
$switchedBackToA = $false
$switchedForwardToB = $false
$failure = $null

try {
    $session = Start-Phase6Session -RepoRoot $repoRoot -ExePath $exeResolved -OutDir $outAbs -Env (New-Phase6Env)
    Wait-Phase6PromptReady -Control $session.Control -TimeoutMs 20000 | Out-Null

    Invoke-Phase6ShellCommand -Control $session.Control -Command (New-Phase6TitleCommand -Title $titleA) | Out-Null
    Wait-Phase6StateTitle -Control $session.Control -Text $titleA -TimeoutMs 15000 | Out-Null
    $stateTitleAOk = $true

    Invoke-Phase6Control -Control $session.Control -Type NEW_TAB | Out-Null
    Wait-Phase6TabCount -Control $session.Control -Expected 2 -TimeoutMs 12000 | Out-Null
    Wait-Phase6ActiveTab -Control $session.Control -Expected 1 -TimeoutMs 12000 | Out-Null
    Wait-Phase6PromptReady -Control $session.Control -TimeoutMs 12000 | Out-Null

    Invoke-Phase6ShellCommand -Control $session.Control -Command (New-Phase6TitleCommand -Title $titleB) | Out-Null
    Wait-Phase6StateTitle -Control $session.Control -Text $titleB -TimeoutMs 15000 | Out-Null
    $stateTitleBOk = $true

    Invoke-Phase6Control -Control $session.Control -Type SWITCH_TAB -TabIndex 0 | Out-Null
    Wait-Phase6ActiveTab -Control $session.Control -Expected 0 -TimeoutMs 12000 | Out-Null
    Wait-Phase6StateTitle -Control $session.Control -Text $titleA -TimeoutMs 12000 | Out-Null
    $switchedBackToA = $true

    Invoke-Phase6Control -Control $session.Control -Type SWITCH_TAB -TabIndex 1 | Out-Null
    Wait-Phase6ActiveTab -Control $session.Control -Expected 1 -TimeoutMs 12000 | Out-Null
    Wait-Phase6StateTitle -Control $session.Control -Text $titleB -TimeoutMs 12000 | Out-Null
    $switchedForwardToB = $true

    $tabsSnapshot = Get-Phase6Tabs -Control $session.Control
} catch {
    $failure = $_.Exception.Message
    if ($session -and $session.Control) {
        try { $tabsSnapshot = Get-Phase6Tabs -Control $session.Control } catch {}
    }
} finally {
    if ($session) {
        $artifacts = Stop-Phase6Session -Session $session -ArtifactPrefix "tab-title-follow"
    }
}
$tab0 = $tabsSnapshot.Tabs | Where-Object { $_.Index -eq 0 } | Select-Object -First 1
$tab1 = $tabsSnapshot.Tabs | Where-Object { $_.Index -eq 1 } | Select-Object -First 1
$pass = ($failure -eq $null) `
    -and ($artifacts.ExitCode -eq 0) `
    -and $stateTitleAOk `
    -and $stateTitleBOk `
    -and $switchedBackToA `
    -and $switchedForwardToB `
    -and $tab0 `
    -and $tab0.Title.Contains($titleA) `
    -and $tab1 `
    -and $tab1.Title.Contains($titleB) `
    -and ($tabsSnapshot.ActiveTab -eq 1)

$detail = "error=$failure state_a=$stateTitleAOk state_b=$stateTitleBOk switch_a=$switchedBackToA switch_b=$switchedForwardToB tab0=$($tab0.Title) tab1=$($tab1.Title) active=$($tabsSnapshot.ActiveTab) exit=$(Format-ExitCode $artifacts.ExitCode)"

Write-TestResult -Id "P6-TITLE" -Name "Phase 6 tab title follows terminal title" -Passed $pass -Detail $detail
Write-Host ("  Debug log : {0}" -f $artifacts.DebugLog)
Write-Host ("  Stderr log: {0}" -f $artifacts.StderrLog)

if (-not $pass) {
    exit 1
}
