param(
    [string]$RepoRoot = "",
    [string]$WinmdPath = "",
    [string]$ToolDir = ""
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$syncScript = Join-Path $RepoRoot "scripts\winui3-sync-delegate-iids.ps1"
if (-not (Test-Path -LiteralPath $syncScript)) {
    $workspaceRoot = Split-Path -Parent $RepoRoot
    if (-not $ToolDir) {
        $ToolDir = Join-Path $workspaceRoot "win-zig-bindgen"
    }
    $syncScript = Join-Path $ToolDir "scripts\winui3-sync-delegate-iids.ps1"
}
if (-not (Test-Path -LiteralPath $syncScript)) {
    throw "Script not found: $syncScript"
}

$args = @("-RepoRoot", $RepoRoot, "-Check")
if ($ToolDir) {
    $args += @("-ToolDir", $ToolDir)
}
if ($WinmdPath) {
    $args += @("-WinmdPath", $WinmdPath)
}

pwsh -File $syncScript @args
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Host "winui3-delegate-iid-check: FAIL (com.zig delegate IID constants are out of sync)"
    exit $exitCode
}

Write-Host "winui3-delegate-iid-check: PASS"
exit 0
