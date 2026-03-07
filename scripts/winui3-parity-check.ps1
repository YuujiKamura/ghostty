param(
    [string]$RepoRoot = "C:\Users\yuuji\ghostty-win",
    [switch]$AutoFix
)
$ErrorActionPreference = "Stop"

$golden = Join-Path $RepoRoot "src\apprt\winui3\com_generated.zig"
$tmpDir = Join-Path $RepoRoot "tmp"
$tmpGen = Join-Path $tmpDir "parity_check.zig"

if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir | Out-Null }

# Regenerate to temp
pwsh -NoProfile -File (Join-Path $RepoRoot "scripts\winui3-regenerate-com.ps1") -OutPath $tmpGen 2>&1 | Out-Null

if (-not (Test-Path $tmpGen)) {
    Write-Error "PARITY CHECK FAILED: Generator produced no output"
    exit 1
}

$diff = Compare-Object (Get-Content $golden) (Get-Content $tmpGen)
if (-not $diff) {
    Write-Host "PARITY CHECK OK: com_generated.zig matches generator output" -ForegroundColor Green
    Remove-Item $tmpGen -ErrorAction SilentlyContinue
    exit 0
}

# Drift detected
Write-Host "PARITY CHECK FAILED: com_generated.zig differs from generator output" -ForegroundColor Red
Write-Host "  Golden:    $golden"
Write-Host "  Generated: $tmpGen"
Write-Host "  Diff lines: $($diff.Count)"

if (-not $AutoFix) {
    Write-Host ""
    $diff | Select-Object -First 20 | ForEach-Object {
        $mark = if ($_.SideIndicator -eq "<=") { "GOLDEN" } else { "GENERATED" }
        Write-Host "  $mark : $($_.InputObject)"
    }
    Write-Host ""
    Write-Host "Fix: update win-zig-bindgen generator, regenerate, and commit."
    Write-Host "  Or rebuild with: zig build -Dapp-runtime=winui3 -Dcom-autofix=true"
    exit 1
}

# AutoFix: invoke guardian.sh --fix
Write-Host ""
Write-Host "=== AutoFix: invoking guardian.sh --fix ===" -ForegroundColor Yellow
$guardianScript = Join-Path $RepoRoot "scripts\guardian.sh"
bash $guardianScript --fix
$guardianExit = $LASTEXITCODE

if ($guardianExit -eq 0) {
    Write-Host "=== AutoFix: guardian resolved drift. Deploying fixed output. ===" -ForegroundColor Green
    # Guardian fixed emit.zig. Regenerate one more time and deploy.
    pwsh -NoProfile -File (Join-Path $RepoRoot "scripts\winui3-regenerate-com.ps1") -OutPath $tmpGen 2>&1 | Out-Null
    Copy-Item $tmpGen $golden -Force
    Write-Host "Deployed updated com_generated.zig. Commit both emit.zig and com_generated.zig."
    exit 0
}

Write-Host "=== AutoFix FAILED (guardian exit $guardianExit). Manual intervention required. ===" -ForegroundColor Red
exit 2
