param(
    [switch]$NoBuild,
    [string]$Optimize = "ReleaseSafe",
    [string]$ExePath,
    [string]$OutDir = "tmp/phase6/resize"
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\winui3-phase6-lib.ps1"

$repoRoot = Get-Phase6RepoRoot
$outAbs = Get-Phase6OutputDir -RepoRoot $repoRoot -OutDir $OutDir
$exeResolved = Resolve-Phase6ExePath -RepoRoot $repoRoot -ExePath $ExePath -Optimize $Optimize -NoBuild:$NoBuild

$session = $null
$artifacts = $null
$resizeTokens = @()
$snapshotMetrics = $null
$snapshotPath = Join-Path $outAbs "resize-final.png"
$failure = $null

try {
    $session = Start-Phase6Session -RepoRoot $repoRoot -ExePath $exeResolved -OutDir $outAbs -Env (New-Phase6Env)
    Wait-Phase6PromptReady -Control $session.Control -TimeoutMs 20000 | Out-Null

    $sizes = @(
        @{ Width = 900; Height = 620; Token = "PHASE6_RESIZE_1" },
        @{ Width = 1180; Height = 780; Token = "PHASE6_RESIZE_2" },
        @{ Width = 1020; Height = 680; Token = "PHASE6_RESIZE_3" }
    )

    foreach ($size in $sizes) {
        Set-Phase6WindowSize -Session $session -Width $size.Width -Height $size.Height
        Start-Sleep -Milliseconds 900
        Invoke-Phase6ShellCommand -Control $session.Control -Command ("echo {0}" -f $size.Token) | Out-Null
        $tail = Wait-Phase6TailContains -Control $session.Control -Text $size.Token -TimeoutMs 12000
        $rect = Get-Phase6WindowRect -Hwnd $session.Hwnd
        $resizeTokens += [pscustomobject]@{
            Token = $size.Token
            TargetWidth = $size.Width
            TargetHeight = $size.Height
            Width = $rect.Width
            Height = $rect.Height
            TailObserved = $tail.Contains($size.Token)
        }
    }

    $snapshotMetrics = Save-Phase6Snapshot -Session $session -Path $snapshotPath
} catch {
    $failure = $_.Exception.Message
} finally {
    if ($session) {
        $artifacts = Stop-Phase6Session -Session $session -ArtifactPrefix "resize"
    }
}
$allResizeTokensObserved = ($resizeTokens.Count -eq 3) -and [bool](@($resizeTokens | Where-Object { -not $_.TailObserved }).Count -eq 0)
$allResizeRectsMatched = ($resizeTokens.Count -eq 3) -and [bool](@($resizeTokens | Where-Object { $_.Width -ne $_.TargetWidth -or $_.Height -ne $_.TargetHeight }).Count -eq 0)
$pass = ($failure -eq $null) -and ($artifacts.ExitCode -eq 0) -and $allResizeTokensObserved -and $allResizeRectsMatched -and $snapshotMetrics.HeaderLikelyVisible
$detail = "error=$failure observed=$allResizeTokensObserved rect_match=$allResizeRectsMatched header_visible=$($snapshotMetrics.HeaderLikelyVisible) exit=$(Format-ExitCode $artifacts.ExitCode)"

Write-TestResult -Id "P6-RESIZE" -Name "Phase 6 resize behavior" -Passed $pass -Detail $detail
Write-Host ("  Snapshot  : {0}" -f $snapshotPath)
Write-Host ("  Debug log : {0}" -f $artifacts.DebugLog)
Write-Host ("  Stderr log: {0}" -f $artifacts.StderrLog)

if (-not $pass) {
    exit 1
}
