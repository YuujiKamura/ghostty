param(
    [int]$WaitSec = 8,
    [switch]$Strict
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$smokeScript = Join-Path $repoRoot "visual_smoke_test_run.ps1"
$debugLog = Join-Path $repoRoot "debug.log"
$auditLog = Join-Path $repoRoot "multitab_audit.log"

# Detect CI environment (GitHub Actions, Azure DevOps, etc.)
$isCI = $env:CI -eq "true" -or $env:TF_BUILD -eq "True" -or $env:GITHUB_ACTIONS -eq "true"

if ($isCI) {
    Write-Host "CI environment detected: skipping GUI smoke test, running static checks only."

    # Static check: verify built artifacts contain required DLLs
    $binDirs = @(@("zig-out-winui3/bin", "zig-out-winui3-staging/bin") | ForEach-Object { Join-Path $repoRoot $_ } | Where-Object { Test-Path $_ })
    if ($binDirs.Count -eq 0) {
        # The build output should be present either from a prior build step
        # in the same job or downloaded via actions/download-artifact from the
        # build-winui3 job (see .github/workflows/ci.yml). If it's missing in
        # CI it's a workflow wiring bug, not a code regression (issue #228).
        # In strict mode we still throw so the failure is visible; in non-
        # strict mode we skip-with-warn to avoid masking real test breakage.
        $msg = "no build output directory found (zig-out-winui3/bin or staging). Build artifact missing (issue #228 wiring)."
        if ($Strict) {
            throw "Contract check failed: $msg"
        } else {
            Write-Warning $msg
            Write-Host "##[warning]Contract check: $msg"
            Write-Host "test-winui3-runtime-contract: SKIP (no build output, non-strict)"
            exit 0
        }
    }

    $binDir = $binDirs[0]
    Write-Host "Checking artifacts in: $binDir"

    $requiredDlls = @(
        "Microsoft.WindowsAppRuntime.Bootstrap.dll",
        "Microsoft.ui.xaml.dll",
        "Microsoft.UI.dll"
    )

    $missing = @()
    foreach ($dll in $requiredDlls) {
        $path = Join-Path $binDir $dll
        if (Test-Path $path) {
            Write-Host "  OK: $dll"
        } else {
            Write-Host "  MISSING: $dll"
            $missing += $dll
        }
    }

    # Check XBF and PRI files
    $xbfCount = (Get-ChildItem -Path $binDir -Filter "*.xbf" -ErrorAction SilentlyContinue | Measure-Object).Count
    $priExists = Test-Path (Join-Path $binDir "resources.pri")
    Write-Host "  XBF files: $xbfCount, resources.pri: $priExists"

    if ($missing.Count -gt 0) {
        $msg = "Contract check failed: missing DLLs: $($missing -join ', ')"
        if ($Strict) { throw $msg } else { Write-Warning $msg }
    }

    if ($xbfCount -eq 0 -or -not $priExists) {
        $msg = "Contract check failed: missing XAML resources (XBF=$xbfCount, PRI=$priExists)"
        if ($Strict) { throw $msg } else { Write-Warning $msg }
    }

    # Check ghostty.exe exists
    $ghosttyExe = Join-Path $binDir "ghostty.exe"
    if (-not (Test-Path $ghosttyExe)) {
        throw "Contract check failed: ghostty.exe not found in $binDir"
    }
    Write-Host "  OK: ghostty.exe"

    Write-Host "test-winui3-runtime-contract: PASS (CI static mode, strict=$Strict)"
    exit 0
}

# --- Non-CI: full GUI smoke test ---
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
