param(
    [int]$WaitSec = 8,
    [switch]$Strict
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$smokeScript = Join-Path $repoRoot "visual_smoke_test_run.ps1"
$debugLog = Join-Path $repoRoot "debug.log"
$auditLog = Join-Path $repoRoot "multitab_audit.log"

if (-not (Test-Path $smokeScript)) {
    throw "Missing smoke script: $smokeScript"
}

$smokeArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $smokeScript,
    "-Runtime", "winui3",
    "-WaitSec", "$WaitSec"
)

if ($Strict) {
    $smokeArgs += @("-FailOnWinRTHresult", "-MaxWinRTHresultCount", "0")
}

Write-Host "Running WinUI3 contract smoke..."
powershell @smokeArgs

if (-not (Test-Path $debugLog)) {
    throw "Missing debug log: $debugLog"
}

$step4Ok = Select-String -Path $debugLog -Pattern "initXaml step 4 OK: HWND=0x" -SimpleMatch
$step4Qi = Select-String -Path $debugLog -Pattern "initXaml step 4: QueryInterface(IWindowNative)" -SimpleMatch
$resourceStep3bFail = Select-String -Path $debugLog -Pattern "loadXamlResources step 3b: get_MergedDictionaries failed" -SimpleMatch
$qiFailure = Select-String -Path $debugLog -Pattern "WinRT HRESULT failed: 0x80004002" -SimpleMatch

$countQiFailure = @($qiFailure).Count

if (-not $step4Qi) {
    throw "Contract check failed: step 4 (QI IWindowNative) was not reached."
}

if (-not $step4Ok) {
    if ($Strict) {
        throw "Contract check failed: step 4 did not complete (no HWND acquired)."
    }
    Write-Warning "Contract warning: step 4 reached but no 'step 4 OK' line found."
}

if ($countQiFailure -gt 0) {
    if ($Strict) {
        throw "Contract check failed: E_NOINTERFACE count=$countQiFailure"
    }
    Write-Warning "Contract warning: E_NOINTERFACE count=$countQiFailure"
}

if ($resourceStep3bFail) {
    if ($Strict) {
        throw "Contract check failed: ResourceDictionary.get_MergedDictionaries failed (step 3b)."
    }
    Write-Warning "Contract warning: ResourceDictionary.get_MergedDictionaries failed (step 3b)."
}

if (Test-Path $auditLog) {
    $runtimeOk = Select-String -Path $auditLog -Pattern "runtime=.winui3" -SimpleMatch
    if (-not $runtimeOk) {
        throw "Contract check failed: runtime was not winui3."
    }
}

Write-Host "test-winui3-runtime-contract: PASS (strict=$Strict, e_nointerface=$countQiFailure)"
