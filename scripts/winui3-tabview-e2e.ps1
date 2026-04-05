param(
    [string]$ExePath = (Join-Path (Split-Path -Parent $PSScriptRoot) "zig-out\bin\ghostty.exe"),
    [int]$TimeoutMs = 20000,
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\winui3-test-lib.ps1"

$repoRoot = Split-Path -Parent $PSScriptRoot
$debugLogPath = Join-Path $repoRoot "debug.log"

function Out-Line([string]$msg, [string]$Color = "") {
    if ($Color) {
        try { [Console]::ForegroundColor = [ConsoleColor]::$Color } catch {}
    }
    [Console]::WriteLine($msg)
    if ($Color) { [Console]::ResetColor() }
}

function Start-Session {
    param(
        [string]$ExePath,
        [string]$TmpDir,
        [hashtable]$Env = @{}
    )

    New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
    $stderrPath = Join-Path $TmpDir "ghostty-stderr-e2e-$timestamp.log"
    "" | Set-Content -Path $stderrPath -Encoding utf8

    $backup = @{}
    foreach ($k in $Env.Keys) {
        $backup[$k] = [Environment]::GetEnvironmentVariable($k, "Process")
        [Environment]::SetEnvironmentVariable($k, [string]$Env[$k], "Process")
    }

    try {
        $proc = Start-Process -FilePath $ExePath `
            -WorkingDirectory (Split-Path -Parent $ExePath) `
            -RedirectStandardError $stderrPath `
            -PassThru
    } finally {
        foreach ($k in $Env.Keys) {
            [Environment]::SetEnvironmentVariable($k, $backup[$k], "Process")
        }
    }

    return [PSCustomObject]@{
        Process = $proc
        StderrPath = $stderrPath
        StartTime = Get-Date
    }
}

function Run-Case {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][hashtable]$Env,
        [Parameter(Mandatory)][scriptblock]$AssertBlock
    )

    $tmpDir = Join-Path (Split-Path -Parent $PSScriptRoot) "tmp"
    "" | Set-Content -Path $debugLogPath -Encoding utf8
    $session = Start-Session -ExePath $ExePath -TmpDir $tmpDir -Env $Env
    $passed = $false
    $detail = ""

    try {
        & $AssertBlock $session
        $passed = $true
        $detail = "ok"
    } catch {
        $detail = $_.Exception.Message
    } finally {
        $exitCode = Stop-Ghostty -Session $session -TimeoutMs 2500
    }

    Write-TestResult -Id $Id -Name $Name -Passed $passed -Detail "$detail (exit=$(Format-ExitCode $exitCode))"
    return [PSCustomObject]@{
        id = $Id
        name = $Name
        passed = $passed
        detail = $detail
        stderr = $session.StderrPath
    }
}

function Wait-LogLineAny {
    param(
        [Parameter(Mandatory)][pscustomobject]$Session,
        [Parameter(Mandatory)][string]$Pattern,
        [int]$TimeoutMs = 10000
    )

    try {
        return Wait-LogLine -Path $Session.StderrPath -Pattern $Pattern -TimeoutMs $TimeoutMs
    } catch {}
    return Wait-LogLine -Path $debugLogPath -Pattern $Pattern -TimeoutMs $TimeoutMs
}

function Has-LogLineAny {
    param(
        [Parameter(Mandatory)][pscustomobject]$Session,
        [Parameter(Mandatory)][string]$Pattern,
        [int]$TimeoutMs = 800
    )

    try {
        Wait-LogLineAny -Session $Session -Pattern $Pattern -TimeoutMs $TimeoutMs | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Find-GhosttyWindowAny {
    param(
        [Parameter(Mandatory)][pscustomobject]$Session,
        [int]$TimeoutMs = 10000
    )

    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        try {
            $Session.Process.Refresh()
            if ($Session.Process.MainWindowHandle -ne 0) {
                return [IntPtr]$Session.Process.MainWindowHandle
            }
        } catch {}
        Start-Sleep -Milliseconds 120
    }

    try {
        return Find-GhosttyWindow -StderrPath $Session.StderrPath -TimeoutMs 1500
    } catch {}

    $line = Wait-LogLine -Path $debugLogPath -Pattern "step 4 OK: HWND=0x" -TimeoutMs 1500
    if ($line -match "HWND=0x([0-9a-fA-F]+)") {
        $hwnd = [IntPtr][System.Convert]::ToInt64($Matches[1], 16)
        if ([Win32]::IsWindowVisible($hwnd)) {
            return $hwnd
        }
    }
    throw "HWND not found in stderr/debug logs"
}

if (-not $NoBuild) {
    Out-Line "[BUILD] zig build -Dapp-runtime=winui3 -Drenderer=d3d11 ..." "Cyan"
    Push-Location $repoRoot
    try {
        zig build -Dapp-runtime=winui3 -Drenderer=d3d11
        if ($LASTEXITCODE -ne 0) { throw "Build failed (exit=$LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
    Out-Line "[BUILD] OK" "Green"
}

$baseEnv = @{}

$results = @()

$results += Run-Case -Id "E2E-1" -Name "TabView parity bootstrap" -Env $baseEnv -AssertBlock {
    param($session)
    Wait-LogLineAny -Session $session -Pattern "validateTabViewParity: ALL CHECKS PASSED" -TimeoutMs $TimeoutMs | Out-Null
    if (Has-LogLineAny -Session $session -Pattern "PARITY_FAIL" -TimeoutMs 1200) {
        throw "unexpected PARITY_FAIL"
    }
}

$envAdd = $baseEnv.Clone()
$results += Run-Case -Id "E2E-2" -Name "Tab added on init" -Env $envAdd -AssertBlock {
    param($session)
    Wait-LogLineAny -Session $session -Pattern "newTab completed: idx=1 total=2" -TimeoutMs $TimeoutMs | Out-Null
    Wait-LogLineAny -Session $session -Pattern "onSelectionChanged" -TimeoutMs $TimeoutMs | Out-Null
}

$envClose = $envAdd.Clone()
$results += Run-Case -Id "E2E-3" -Name "Close one tab keeps app alive" -Env $envClose -AssertBlock {
    param($session)
    Wait-LogLineAny -Session $session -Pattern "newTab completed: idx=1 total=2" -TimeoutMs $TimeoutMs | Out-Null
    Start-Sleep -Milliseconds 300
    Send-KeyCombo -Modifier 0x11 -Key 0x57 | Out-Null # Ctrl+W
    Start-Sleep -Milliseconds 900
    if ($session.Process.HasExited) {
        throw "process exited after closing one tab"
    }
    $logAll = @(
        (Get-Content -Path $session.StderrPath -Raw -ErrorAction SilentlyContinue),
        (Get-Content -Path $debugLogPath -Raw -ErrorAction SilentlyContinue)
    ) -join "`n"
    if ($logAll -match "closeTab: no tabs remain, requesting app exit") {
        throw "all tabs closed unexpectedly"
    }
}

$passCount = ($results | Where-Object { $_.passed }).Count
$failCount = $results.Count - $passCount

Out-Line ""
Out-Line "TabView E2E: $passCount/$($results.Count) PASS, $failCount FAIL" $(if ($failCount -eq 0) { "Green" } else { "Red" })
foreach ($r in $results) {
    Out-Line ("  {0}: {1}" -f $r.id, $r.stderr)
}

if ($failCount -gt 0) {
    exit 1
}
