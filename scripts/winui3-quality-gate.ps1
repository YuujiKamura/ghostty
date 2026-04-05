param(
    [ValidateSet("winui3","win32")][string]$Runtime = "winui3",
    [switch]$NoBuild,
    [int]$HoldSec = 10,
    [string]$OutDir = "tmp/quality-gate"
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\winui3-test-lib.ps1"

$repoRoot = Split-Path -Parent $PSScriptRoot
$debugLogPath = Join-Path $repoRoot "debug.log"
$tmpDir = Join-Path $repoRoot "tmp"
$outAbs = Join-Path $repoRoot $OutDir
New-Item -ItemType Directory -Path $outAbs -Force | Out-Null

function Set-EnvMap {
    param([hashtable]$Map)
    $backup = @{}
    foreach ($k in $Map.Keys) {
        $backup[$k] = [Environment]::GetEnvironmentVariable($k, "Process")
        [Environment]::SetEnvironmentVariable($k, [string]$Map[$k], "Process")
    }
    return $backup
}

function Restore-EnvMap {
    param([hashtable]$Backup)
    foreach ($k in $Backup.Keys) {
        [Environment]::SetEnvironmentVariable($k, $Backup[$k], "Process")
    }
}

function Find-GhosttyWindowAny {
    param(
        [Parameter(Mandatory)][pscustomobject]$Session,
        [int]$TimeoutMs = 20000
    )
    try {
        return Find-GhosttyWindow -StderrPath $Session.StderrPath -TimeoutMs 1500
    } catch {}

    $line = Wait-LogLine -Path $debugLogPath -Pattern "step 4 OK: HWND=0x" -TimeoutMs $TimeoutMs
    if ($line -match "HWND=0x([0-9a-fA-F]+)") {
        $hwnd = [IntPtr][System.Convert]::ToInt64($Matches[1], 16)
        if ([Win32]::IsWindowVisible($hwnd)) { return $hwnd }
    }
    throw "HWND not found from stderr/debug log"
}

function Has-LogLine {
    param([string]$Path, [string]$Pattern)
    if (-not (Test-Path $Path)) { return $false }
    return [bool](Select-String -Path $Path -Pattern $Pattern -SimpleMatch -ErrorAction SilentlyContinue)
}

function Count-LogLine {
    param([string]$Path, [string]$Pattern)
    if (-not (Test-Path $Path)) { return 0 }
    return @((Select-String -Path $Path -Pattern $Pattern -SimpleMatch -ErrorAction SilentlyContinue)).Count
}

function Get-HeaderVisualMetrics {
    param([Parameter(Mandatory)][System.Drawing.Bitmap]$Bitmap)

    $w = $Bitmap.Width
    $h = $Bitmap.Height
    $bandH = [Math]::Min(96, [Math]::Max(24, [int]($h * 0.14)))
    $step = 4
    $sum = 0.0
    $sum2 = 0.0
    $count = 0
    $nonBlack = 0

    for ($y = 0; $y -lt $bandH; $y += $step) {
        for ($x = 0; $x -lt $w; $x += $step) {
            $c = $Bitmap.GetPixel($x, $y)
            $lum = (0.2126 * $c.R) + (0.7152 * $c.G) + (0.0722 * $c.B)
            $sum += $lum
            $sum2 += ($lum * $lum)
            if (($c.R + $c.G + $c.B) -gt 12) { $nonBlack++ }
            $count++
        }
    }

    if ($count -le 0) {
        return [PSCustomObject]@{
            HeaderBandHeight = $bandH
            LumaStdDev = 0.0
            NonBlackRatio = 0.0
            HeaderLikelyVisible = $false
        }
    }

    $mean = $sum / $count
    $var = ($sum2 / $count) - ($mean * $mean)
    if ($var -lt 0) { $var = 0 }
    $std = [Math]::Sqrt($var)
    $nonBlackRatio = [double]$nonBlack / [double]$count
    $headerLikelyVisible = ($std -ge 6.0) -and ($nonBlackRatio -ge 0.08)

    return [PSCustomObject]@{
        HeaderBandHeight = $bandH
        LumaStdDev = [Math]::Round($std, 3)
        NonBlackRatio = [Math]::Round($nonBlackRatio, 4)
        HeaderLikelyVisible = $headerLikelyVisible
    }
}

function Get-UiaMetrics {
    param([Parameter(Mandatory)][IntPtr]$Hwnd)

    $result = [PSCustomObject]@{
        Available = $false
        TabCount = -1
        TabItemCount = -1
    }

    try {
        Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop | Out-Null
        Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop | Out-Null
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
        if ($null -eq $root) { return $result }

        $condTab = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Tab
        )
        $condTabItem = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::TabItem
        )
        $tabs = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condTab)
        $tabItems = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condTabItem)
        $result.Available = $true
        $result.TabCount = $tabs.Count
        $result.TabItemCount = $tabItems.Count
        return $result
    } catch {
        return $result
    }
}

if (-not $NoBuild) {
    Push-Location $repoRoot
    try {
        $buildArgs = @("build", "-Dapp-runtime=$Runtime")
        if ($Runtime -eq "winui3") {
            $buildArgs += "-Drenderer=d3d11"
        }
        & zig @buildArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Build failed (exit code $LASTEXITCODE): zig $($buildArgs -join ' ')"
        }
    } finally {
        Pop-Location
    }
}

$exePath = Join-Path $repoRoot "zig-out\bin\ghostty.exe"
$exeWorkDir = Join-Path $repoRoot "zig-out\bin"
if (-not (Test-Path $exePath)) {
    throw "Executable not found after build: $exePath"
}

$profiles = @(
    @{
        Name = "baseline"
        Env = @{}
    }
)

$results = @()

foreach ($profile in $profiles) {
    $name = $profile.Name
    Write-Host "=== profile: $name ===" -ForegroundColor Cyan
    "" | Set-Content -Path $debugLogPath -Encoding utf8

    $envMap = @{}
    foreach ($k in $profile.Env.Keys) { $envMap[$k] = $profile.Env[$k] }
    $backup = Set-EnvMap -Map $envMap

    $session = $null
    $hwnd = [IntPtr]::Zero
    $aliveAfterHold = $false
    $exitCode = $null
    $screenPath = Join-Path $outAbs "$name.png"
    $logPath = Join-Path $outAbs "$name.debug.log"
    $stderrPath = $null
    $uia = $null
    $vis = $null

    try {
        $session = Start-Ghostty -ExePath $exePath -TmpDir $tmpDir -WorkingDirectory $exeWorkDir
        $stderrPath = $session.StderrPath
        $hwnd = Find-GhosttyWindowAny -Session $session -TimeoutMs 20000
        Start-Sleep -Milliseconds 1800

        $bmp = Get-WindowVisualSnapshot -Hwnd $hwnd
        try {
            $bmp.Save($screenPath, [System.Drawing.Imaging.ImageFormat]::Png)
            $vis = Get-HeaderVisualMetrics -Bitmap $bmp
        } finally {
            $bmp.Dispose()
        }
        $uia = Get-UiaMetrics -Hwnd $hwnd

        Start-Sleep -Seconds $HoldSec
        $aliveAfterHold = -not $session.Process.HasExited
        if ($aliveAfterHold) {
            $exitCode = Stop-Ghostty -Session $session -TimeoutMs 3000
        } else {
            $exitCode = $session.Process.ExitCode
        }
    } catch {
        $exitCode = if ($session -and $session.Process) { $session.Process.ExitCode } else { -99999 }
    } finally {
        if ($session -and $session.Process -and -not $session.Process.HasExited) {
            try { Stop-Process -Id $session.Process.Id -Force } catch {}
        }
        if (Test-Path $debugLogPath) {
            Copy-Item -Path $debugLogPath -Destination $logPath -Force
        }
        Restore-EnvMap -Backup $backup
    }

    $tabCreationFailed = Has-LogLine -Path $logPath -Pattern "TabView creation failed"
    $parityPass = Has-LogLine -Path $logPath -Pattern "validateTabViewParity: ALL CHECKS PASSED"
    $parityFail = Count-LogLine -Path $logPath -Pattern "PARITY_FAIL"
    $hresultCount = Count-LogLine -Path $logPath -Pattern "WinRT HRESULT failed:"
    $resourceOk = Has-LogLine -Path $logPath -Pattern "loadXamlResources: OK primary path"

    $results += [PSCustomObject]@{
        profile = $name
        exit_code = $exitCode
        exit_text = (Format-ExitCode ([int]$exitCode))
        alive_after_hold = $aliveAfterHold
        tab_creation_failed = $tabCreationFailed
        parity_pass = $parityPass
        parity_fail_count = $parityFail
        winrt_hresult_count = $hresultCount
        resource_bootstrap_ok = $resourceOk
        header_likely_visible = if ($vis) { $vis.HeaderLikelyVisible } else { $false }
        header_luma_stddev = if ($vis) { $vis.LumaStdDev } else { 0.0 }
        header_nonblack_ratio = if ($vis) { $vis.NonBlackRatio } else { 0.0 }
        uia_available = if ($uia) { $uia.Available } else { $false }
        uia_tab_count = if ($uia) { $uia.TabCount } else { -1 }
        uia_tabitem_count = if ($uia) { $uia.TabItemCount } else { -1 }
        screenshot = $screenPath
        debug_log = $logPath
        stderr_log = $stderrPath
    }
}

$jsonPath = Join-Path $outAbs "summary.json"
$mdPath = Join-Path $outAbs "summary.md"
$results | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8

$md = @()
$md += "# WinUI3 Quality Gate"
$md += ""
$md += "| profile | alive_after_hold | exit | tab_creation_failed | parity_pass | parity_fail_count | hresult_count | header_visible | uia_tabs | uia_tabitems |"
$md += "|---|---:|---|---:|---:|---:|---:|---:|---:|---:|"
foreach ($r in $results) {
    $md += "| $($r.profile) | $($r.alive_after_hold) | $($r.exit_text) | $($r.tab_creation_failed) | $($r.parity_pass) | $($r.parity_fail_count) | $($r.winrt_hresult_count) | $($r.header_likely_visible) | $($r.uia_tab_count) | $($r.uia_tabitem_count) |"
}
$md += ""
$md += "Artifacts:"
foreach ($r in $results) {
    $md += "- $($r.profile): screenshot=$($r.screenshot), debug=$($r.debug_log), stderr=$($r.stderr_log)"
}
$md | Set-Content -Path $mdPath -Encoding UTF8

$results | Format-Table profile,alive_after_hold,exit_text,tab_creation_failed,parity_pass,winrt_hresult_count,header_likely_visible,uia_tab_count,uia_tabitem_count -AutoSize
Write-Host "wrote: $jsonPath"
Write-Host "wrote: $mdPath"
