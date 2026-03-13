param(
    [switch]$NoBuild,
    [string]$Optimize = "ReleaseSafe",
    [string]$ExePath,
    [string]$OutDir = "tmp/phase6/exit-clean"
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\winui3-phase6-lib.ps1"

$repoRoot = Get-Phase6RepoRoot
$outAbs = Get-Phase6OutputDir -RepoRoot $repoRoot -OutDir $OutDir
$exeResolved = Resolve-Phase6ExePath -RepoRoot $repoRoot -ExePath $ExePath -Optimize $Optimize -NoBuild:$NoBuild

$session = $null
$artifacts = $null
$failure = $null

try {
    $session = Start-Phase6Session -RepoRoot $repoRoot -ExePath $exeResolved -OutDir $outAbs -Env (New-Phase6Env)
    Wait-Phase6PromptReady -Control $session.Control -TimeoutMs 20000 | Out-Null

    Invoke-Phase6Control -Control $session.Control -Type NEW_TAB | Out-Null
    Wait-Phase6TabCount -Control $session.Control -Expected 2 -TimeoutMs 12000 | Out-Null
    Wait-Phase6ActiveTab -Control $session.Control -Expected 1 -TimeoutMs 12000 | Out-Null
    Wait-Phase6PromptReady -Control $session.Control -TimeoutMs 12000 | Out-Null

    Invoke-Phase6Control -Control $session.Control -Type SWITCH_TAB -TabIndex 0 | Out-Null
    Wait-Phase6ActiveTab -Control $session.Control -Expected 0 -TimeoutMs 12000 | Out-Null
    Wait-Phase6PromptReady -Control $session.Control -TimeoutMs 12000 | Out-Null
    Invoke-Phase6ShellCommand -Control $session.Control -Command "echo PHASE6_EXIT_OK" | Out-Null
    Wait-Phase6TailContains -Control $session.Control -Text "PHASE6_EXIT_OK" -TimeoutMs 12000 | Out-Null
} catch {
    $failure = $_.Exception.Message
} finally {
    if ($session) {
        $artifacts = Stop-Phase6Session -Session $session -ArtifactPrefix "exit-clean"
    }
}

$combinedText = @()
if ($artifacts -and (Test-Path $artifacts.DebugLog)) {
    $combinedText += (Get-Content -Path $artifacts.DebugLog -Raw -ErrorAction SilentlyContinue)
}
if ($artifacts -and (Test-Path $artifacts.StderrLog)) {
    $combinedText += (Get-Content -Path $artifacts.StderrLog -Raw -ErrorAction SilentlyContinue)
}
$combinedText = ($combinedText -join "`n")

$wmCloseSeen = $combinedText.Contains("WM_CLOSE received")
$closeRequested = $combinedText.Contains("requestCloseWindow called!")
$windowClosed = $combinedText.Contains("onWindowClosed called!")
$crashSignature = $combinedText -match "STATUS_STOWED_EXCEPTION|STATUS_ACCESS_VIOLATION|segfault|access violation|heap corruption"
$pass = ($failure -eq $null) -and ($artifacts.ExitCode -eq 0) -and $wmCloseSeen -and $closeRequested -and $windowClosed -and (-not $crashSignature)
$detail = "error=$failure wm_close=$wmCloseSeen request_close=$closeRequested window_closed=$windowClosed crash_signature=$crashSignature exit=$(Format-ExitCode $artifacts.ExitCode)"

Write-TestResult -Id "P6-EXIT" -Name "Phase 6 clean exit without segfault" -Passed $pass -Detail $detail
Write-Host ("  Debug log : {0}" -f $artifacts.DebugLog)
Write-Host ("  Stderr log: {0}" -f $artifacts.StderrLog)

if (-not $pass) {
    exit 1
}
