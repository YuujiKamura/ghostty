param(
    [string]$RepoRoot = "C:\Users\yuuji\ghostty-win"
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
if ($diff) {
    Write-Host "PARITY CHECK FAILED: com_generated.zig differs from generator output" -ForegroundColor Red
    Write-Host "  Golden:    $golden"
    Write-Host "  Generated: $tmpGen"
    Write-Host ""
    Write-Host "Diff ($($diff.Count) lines):"
    $diff | Select-Object -First 20 | ForEach-Object {
        $mark = if ($_.SideIndicator -eq "<=") { "GOLDEN" } else { "GENERATED" }
        Write-Host "  $mark : $($_.InputObject)"
    }
    Write-Host ""
    Write-Host "Fix: update win-zig-bindgen generator, regenerate, and commit."
    Write-Host "Do NOT hand-edit com_generated.zig."
    exit 1
}

Write-Host "PARITY CHECK OK: com_generated.zig matches generator output" -ForegroundColor Green
Remove-Item $tmpGen -ErrorAction SilentlyContinue
exit 0
