# run-failed.ps1 — Re-run only previously failed tests
# Usage: pwsh.exe -File run-failed.ps1 [-ExePath path]

param(
    [string]$ExePath,
    [switch]$SkipBuild
)

$script = Join-Path $PSScriptRoot "run-all-tests.ps1"
$params = @{ OnlyFailed = $true }
if ($ExePath) { $params.ExePath = $ExePath }
if ($SkipBuild) { $params.SkipBuild = $true }

& $script @params
exit $LASTEXITCODE
