param(
    [switch]$NoBuild,
    [string]$Optimize = "ReleaseSafe",
    [string]$ExePath,
    [string]$OutDir = "tmp/phase6/tabview-switch"
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\winui3-phase6-lib.ps1"

$repoRoot = Get-Phase6RepoRoot
$outAbs = Get-Phase6OutputDir -RepoRoot $repoRoot -OutDir $OutDir
$exeResolved = Resolve-Phase6ExePath -RepoRoot $repoRoot -ExePath $ExePath -Optimize $Optimize -NoBuild:$NoBuild

$session = $null
$artifacts = $null
$tab0Shot = Join-Path $outAbs "tab0-active.png"
$tab1Shot = Join-Path $outAbs "tab1-active.png"
$tab0Metrics = $null
$tab1Metrics = $null
$tail0 = ""
$tail1 = ""
$visualDiffRatio = 0.0
$failure = $null

try {
    $session = Start-Phase6Session -RepoRoot $repoRoot -ExePath $exeResolved -OutDir $outAbs -Env (New-Phase6Env)
    Wait-Phase6PromptReady -Control $session.Control -TimeoutMs 20000 | Out-Null
    Wait-Phase6TabCount -Control $session.Control -Expected 1 -TimeoutMs 10000 | Out-Null

    Invoke-Phase6ShellCommand -Control $session.Control -Command "echo PHASE6_TAB0" | Out-Null
    Wait-Phase6TailContains -Control $session.Control -Text "PHASE6_TAB0" -TimeoutMs 12000 | Out-Null

    Invoke-Phase6Control -Control $session.Control -Type NEW_TAB | Out-Null
    Wait-Phase6TabCount -Control $session.Control -Expected 2 -TimeoutMs 12000 | Out-Null
    Wait-Phase6ActiveTab -Control $session.Control -Expected 1 -TimeoutMs 12000 | Out-Null
    Wait-Phase6PromptReady -Control $session.Control -TimeoutMs 12000 | Out-Null

    Invoke-Phase6ShellCommand -Control $session.Control -Command "echo PHASE6_TAB1" | Out-Null
    Wait-Phase6TailContains -Control $session.Control -Text "PHASE6_TAB1" -TimeoutMs 12000 | Out-Null

    Invoke-Phase6Control -Control $session.Control -Type SWITCH_TAB -TabIndex 0 | Out-Null
    Wait-Phase6ActiveTab -Control $session.Control -Expected 0 -TimeoutMs 12000 | Out-Null
    Wait-Phase6PromptReady -Control $session.Control -TimeoutMs 12000 | Out-Null
    $tail0 = Wait-Phase6TailContains -Control $session.Control -Text "PHASE6_TAB0" -TimeoutMs 12000 -Lines 80
    $tab0Metrics = Save-Phase6Snapshot -Session $session -Path $tab0Shot

    Invoke-Phase6Control -Control $session.Control -Type SWITCH_TAB -TabIndex 1 | Out-Null
    Wait-Phase6ActiveTab -Control $session.Control -Expected 1 -TimeoutMs 12000 | Out-Null
    Wait-Phase6PromptReady -Control $session.Control -TimeoutMs 12000 | Out-Null
    $tail1 = Wait-Phase6TailContains -Control $session.Control -Text "PHASE6_TAB1" -TimeoutMs 12000 -Lines 80
    $tab1Metrics = Save-Phase6Snapshot -Session $session -Path $tab1Shot
} catch {
    $failure = $_.Exception.Message
} finally {
    if ($session) {
        $artifacts = Stop-Phase6Session -Session $session -ArtifactPrefix "tabview-switch"
    }
}

if ((Test-Path $tab0Shot) -and (Test-Path $tab1Shot)) {
    $bmp0 = [System.Drawing.Bitmap]::FromFile($tab0Shot)
    try {
        $bmp1 = [System.Drawing.Bitmap]::FromFile($tab1Shot)
        try {
            $visualDiffRatio = Get-VisualDiffRatioBetween -Before $bmp0 -After $bmp1 -SampleStep 8 -ColorThreshold 30
        } finally {
            $bmp1.Dispose()
        }
    } finally {
        $bmp0.Dispose()
    }
}

$pass = $artifacts.ExitCode -eq 0 `
    -and ($failure -eq $null) `
    -and $tail0.Contains("PHASE6_TAB0") `
    -and $tail1.Contains("PHASE6_TAB1") `
    -and $tab0Metrics `
    -and $tab0Metrics.HeaderLikelyVisible `
    -and $tab1Metrics `
    -and $tab1Metrics.HeaderLikelyVisible

$detail = "error=$failure diff=$([Math]::Round($visualDiffRatio, 4)) header0=$($tab0Metrics.HeaderLikelyVisible) header1=$($tab1Metrics.HeaderLikelyVisible) exit=$(Format-ExitCode $artifacts.ExitCode)"

Write-TestResult -Id "P6-TAB-SWITCH" -Name "Phase 6 TabView display and switch" -Passed $pass -Detail $detail
Write-Host ("  Tab0 shot : {0}" -f $tab0Shot)
Write-Host ("  Tab1 shot : {0}" -f $tab1Shot)
Write-Host ("  Debug log : {0}" -f $artifacts.DebugLog)
Write-Host ("  Stderr log: {0}" -f $artifacts.StderrLog)

if (-not $pass) {
    exit 1
}
