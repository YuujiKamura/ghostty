param(
    [string]$RepoRoot = "C:\Users\yuuji\ghostty-win",
    [switch]$AutoFix
)
$ErrorActionPreference = "Stop"

$golden = Join-Path $RepoRoot "src\apprt\winui3\com_generated.zig"
$backupDir = Join-Path $RepoRoot "tmp\com_backups"
$tmpDir = Join-Path $RepoRoot "tmp"
$tmpGen = Join-Path $tmpDir "parity_check.zig"

if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir | Out-Null }
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }

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

# === AutoFix with rollback safety ===

# Step 1: Backup current working golden BEFORE any modification
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupPath = Join-Path $backupDir "com_generated_$timestamp.zig"
Copy-Item $golden $backupPath -Force
Write-Host ""
Write-Host "=== Backed up working golden to: $backupPath ===" -ForegroundColor Cyan

# Also backup emit.zig
$emitZig = Join-Path $env:USERPROFILE "win-zig-bindgen\emit.zig"
$emitBackup = Join-Path $backupDir "emit_$timestamp.zig"
if (Test-Path $emitZig) {
    Copy-Item $emitZig $emitBackup -Force
    Write-Host "=== Backed up emit.zig to: $emitBackup ===" -ForegroundColor Cyan
}

# Step 2: Run guardian.sh --fix
Write-Host ""
Write-Host "=== AutoFix: invoking guardian.sh --fix ===" -ForegroundColor Yellow
$guardianScript = Join-Path $RepoRoot "scripts\guardian.sh"
bash $guardianScript --fix
$guardianExit = $LASTEXITCODE

if ($guardianExit -ne 0) {
    Write-Host "=== AutoFix: guardian failed. Rolling back. ===" -ForegroundColor Red
    Copy-Item $backupPath $golden -Force
    if (Test-Path $emitBackup) { Copy-Item $emitBackup $emitZig -Force }
    Write-Host "Rolled back to: $backupPath"
    exit 2
}

# Step 3: Guardian claims success. Regenerate and deploy.
Write-Host "=== Guardian resolved drift. Rebuilding app to verify... ===" -ForegroundColor Yellow
pwsh -NoProfile -File (Join-Path $RepoRoot "scripts\winui3-regenerate-com.ps1") -OutPath $tmpGen 2>&1 | Out-Null
Copy-Item $tmpGen $golden -Force

# Step 4: Build the app
Push-Location $RepoRoot
$buildOk = $false
try {
    # Build without parity check (we just deployed, it would match)
    zig build -Dapp-runtime=winui3 2>&1 | Out-Null
    $buildOk = ($LASTEXITCODE -eq 0)
} catch {
    $buildOk = $false
}
Pop-Location

if (-not $buildOk) {
    Write-Host "=== BUILD FAILED after autofix. Rolling back. ===" -ForegroundColor Red
    Copy-Item $backupPath $golden -Force
    if (Test-Path $emitBackup) { Copy-Item $emitBackup $emitZig -Force }
    Write-Host "Rolled back to: $backupPath"
    exit 2
}

# Step 5: Vtable manifest verification (replaces smoke test)
Write-Host "=== Verifying vtable manifest... ===" -ForegroundColor Yellow
$manifestPath = Join-Path $RepoRoot "contracts\vtable_manifest.json"
if (Test-Path $manifestPath) {
    $verifyScript = Join-Path $RepoRoot "scripts\verify-vtable-manifest.ps1"
    pwsh -NoProfile -File $verifyScript -ComGenPath $golden -ManifestPath $manifestPath
    if ($LASTEXITCODE -ne 0) {
        Write-Host "=== VTABLE MANIFEST MISMATCH after autofix. Rolling back. ===" -ForegroundColor Red
        Copy-Item $backupPath $golden -Force
        if (Test-Path $emitBackup) { Copy-Item $emitBackup $emitZig -Force }
        Write-Host "Rolled back to: $backupPath"
        exit 2
    }
    Write-Host "=== Vtable manifest verified ===" -ForegroundColor Green
} else {
    Write-Host "WARNING: vtable_manifest.json not found at $manifestPath, skipping structural verification" -ForegroundColor Yellow
}

# Step 6: Success
Write-Host ""
Write-Host "=== AutoFix COMPLETE ===" -ForegroundColor Green
Write-Host "  Backup: $backupPath"
Write-Host "  Commit both emit.zig and com_generated.zig."

# Prune old backups (keep last 5)
$old = Get-ChildItem $backupDir -Filter "com_generated_*.zig" | Sort-Object Name -Descending | Select-Object -Skip 5
$old += Get-ChildItem $backupDir -Filter "emit_*.zig" | Sort-Object Name -Descending | Select-Object -Skip 5
$old | Remove-Item -Force -ErrorAction SilentlyContinue

exit 0
