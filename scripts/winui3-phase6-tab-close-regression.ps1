param(
    [switch]$NoBuild,
    [string]$Optimize = "ReleaseSafe",
    [string]$ExePath,
    [string]$OutDir = "tmp/phase6/tab-close-regression"
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\winui3-phase6-lib.ps1"

$repoRoot = Get-Phase6RepoRoot
$outAbs = Get-Phase6OutputDir -RepoRoot $repoRoot -OutDir $OutDir
$exeResolved = Resolve-Phase6ExePath -RepoRoot $repoRoot -ExePath $ExePath -Optimize $Optimize -NoBuild:$NoBuild

$session = $null
$artifacts = $null
$failure = $null
$tailAfterClose = ""
$tailAfterEcho = ""
$tab0Shot = Join-Path $outAbs "tab0-before-close.png"
$tab1Shot = Join-Path $outAbs "tab1-before-close.png"
$afterCloseShot = Join-Path $outAbs "tab0-after-close.png"
$tab0Metrics = $null
$tab1Metrics = $null
$afterCloseMetrics = $null
$diffTab0ToAfter = 1.0
$diffTab1ToAfter = 1.0

$marker0 = "ISSUE129_TAB0"
$marker1 = "ISSUE129_TAB1"
$markerAfter = "ISSUE129_AFTER_CLOSE"
$fill0 = "ISSUE129_TAB0_FILL_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
$fill1 = "ISSUE129_TAB1_FILL_ZYXWVUTSRQPONMLKJIHGFEDCBA9876543210"
$cmd0 = "cls & for /l %i in (1,1,24) do @echo $fill0"
$cmd1 = "cls & for /l %i in (1,1,24) do @echo $fill1"

try {
    $session = Start-Phase6Session -RepoRoot $repoRoot -ExePath $exeResolved -OutDir $outAbs -Env (New-Phase6Env)
    Wait-Phase6PromptReady -Control $session.Control -TimeoutMs 20000 | Out-Null
    Wait-Phase6TabCount -Control $session.Control -Expected 1 -TimeoutMs 10000 | Out-Null
    Wait-Phase6ActiveTab -Control $session.Control -Expected 0 -TimeoutMs 10000 | Out-Null

    Invoke-Phase6ShellCommand -Control $session.Control -Command $cmd0 | Out-Null
    Wait-Phase6TailContains -Control $session.Control -Text $marker0 -TimeoutMs 12000 | Out-Null
    $tab0Metrics = Save-Phase6Snapshot -Session $session -Path $tab0Shot

    Invoke-Phase6Control -Control $session.Control -Type NEW_TAB | Out-Null
    Wait-Phase6TabCount -Control $session.Control -Expected 2 -TimeoutMs 12000 | Out-Null
    Wait-Phase6ActiveTab -Control $session.Control -Expected 1 -TimeoutMs 12000 | Out-Null
    Wait-Phase6PromptReady -Control $session.Control -TimeoutMs 12000 | Out-Null

    Invoke-Phase6ShellCommand -Control $session.Control -Command $cmd1 | Out-Null
    Wait-Phase6TailContains -Control $session.Control -Text $marker1 -TimeoutMs 12000 | Out-Null
    $tab1Metrics = Save-Phase6Snapshot -Session $session -Path $tab1Shot

    Invoke-Phase6Control -Control $session.Control -Type CLOSE_TAB -TabIndex 1 | Out-Null
    Wait-Phase6TabCount -Control $session.Control -Expected 1 -TimeoutMs 12000 | Out-Null
    Wait-Phase6ActiveTab -Control $session.Control -Expected 0 -TimeoutMs 12000 | Out-Null
    Wait-Phase6PromptReady -Control $session.Control -TimeoutMs 12000 | Out-Null

    $tailAfterClose = Wait-Phase6TailContains -Control $session.Control -Text $marker0 -TimeoutMs 12000 -Lines 80
    if ($tailAfterClose.Contains($marker1)) {
        throw "closed tab marker still visible after closing tab 1"
    }
    $afterCloseMetrics = Save-Phase6Snapshot -Session $session -Path $afterCloseShot

    Invoke-Phase6ShellCommand -Control $session.Control -Command "echo $markerAfter" | Out-Null
    $tailAfterEcho = Wait-Phase6TailContains -Control $session.Control -Text $markerAfter -TimeoutMs 12000 -Lines 80
    if (-not $tailAfterEcho.Contains($marker0)) {
        throw "restored tab tail no longer contains original tab marker"
    }
} catch {
    $failure = $_.Exception.Message
} finally {
    if ($session) {
        $artifacts = Stop-Phase6Session -Session $session -ArtifactPrefix "tab-close-regression"
    }
}

if ((Test-Path $tab0Shot) -and (Test-Path $tab1Shot) -and (Test-Path $afterCloseShot)) {
    $bmp0 = [System.Drawing.Bitmap]::FromFile($tab0Shot)
    try {
        $bmp1 = [System.Drawing.Bitmap]::FromFile($tab1Shot)
        try {
            $bmpAfter = [System.Drawing.Bitmap]::FromFile($afterCloseShot)
            try {
                $diffTab0ToAfter = Get-VisualDiffRatioBetween -Before $bmp0 -After $bmpAfter -SampleStep 8 -ColorThreshold 30
                $diffTab1ToAfter = Get-VisualDiffRatioBetween -Before $bmp1 -After $bmpAfter -SampleStep 8 -ColorThreshold 30
            } finally {
                $bmpAfter.Dispose()
            }
        } finally {
            $bmp1.Dispose()
        }
    } finally {
        $bmp0.Dispose()
    }
}

$pass = ($failure -eq $null) `
    -and ($tailAfterClose.Contains($marker0)) `
    -and (-not $tailAfterClose.Contains($marker1)) `
    -and ($tailAfterEcho.Contains($markerAfter)) `
    -and ($tailAfterEcho.Contains($marker0)) `
    -and $tab0Metrics `
    -and $tab0Metrics.HeaderLikelyVisible `
    -and $tab1Metrics `
    -and $tab1Metrics.HeaderLikelyVisible `
    -and $afterCloseMetrics `
    -and $afterCloseMetrics.HeaderLikelyVisible `
    -and ($diffTab0ToAfter -lt 0.12) `
    -and ($diffTab0ToAfter -lt $diffTab1ToAfter) `
    -and ($artifacts.ExitCode -eq 0)

$detail = "error=$failure tail_restored=$($tailAfterClose.Contains($marker0)) tail_closed_marker_present=$($tailAfterClose.Contains($marker1)) post_close_echo=$($tailAfterEcho.Contains($markerAfter)) header0=$($tab0Metrics.HeaderLikelyVisible) header1=$($tab1Metrics.HeaderLikelyVisible) header_after=$($afterCloseMetrics.HeaderLikelyVisible) diff_tab0_after=$([Math]::Round($diffTab0ToAfter,4)) diff_tab1_after=$([Math]::Round($diffTab1ToAfter,4)) exit=$(Format-ExitCode $artifacts.ExitCode)"

Write-TestResult -Id "P6-TAB-CLOSE-129" -Name "Phase 6 Issue #129 tab close regression" -Passed $pass -Detail $detail
Write-Host ("  Tab0 shot : {0}" -f $tab0Shot)
Write-Host ("  Tab1 shot : {0}" -f $tab1Shot)
Write-Host ("  After shot: {0}" -f $afterCloseShot)
Write-Host ("  Debug log : {0}" -f $artifacts.DebugLog)
Write-Host ("  Stderr log: {0}" -f $artifacts.StderrLog)

if (-not $pass) {
    exit 1
}
