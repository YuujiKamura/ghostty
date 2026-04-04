param(
    [string]$RepoRoot = ".",
    [string]$Golden = "src/apprt/gtk",
    [string]$Candidate = "src/apprt/winui3",
    [string]$AuditReport = "tmp/winui3-test-parity-audit.md",
    [string]$Mapping = "",
    [string]$Backend = "gemini",
    [string]$AiCodeReviewRoot = (Join-Path $HOME "ai-code-review")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoAbs = (Resolve-Path $RepoRoot).Path
$goldenAbs = Join-Path $repoAbs $Golden
$candidateAbs = Join-Path $repoAbs $Candidate
$auditAbs = Join-Path $repoAbs $AuditReport

if (-not (Test-Path $goldenAbs)) { throw "Golden path not found: $goldenAbs" }
if (-not (Test-Path $candidateAbs)) { throw "Candidate path not found: $candidateAbs" }

$cargoToml = Join-Path $AiCodeReviewRoot "Cargo.toml"
if (-not (Test-Path $cargoToml)) {
    throw "ai-code-review Cargo.toml not found: $cargoToml"
}

$auditDir = Split-Path -Parent $auditAbs
if ($auditDir -and -not (Test-Path $auditDir)) {
    New-Item -ItemType Directory -Path $auditDir -Force | Out-Null
}

function Resolve-CorpusPath {
    param(
        [Parameter(Mandatory)][string]$InputPath,
        [Parameter(Mandatory)][string]$Label
    )

    $item = Get-Item -LiteralPath $InputPath
    if ($item.PSIsContainer -eq $false) {
        return $item.FullName
    }

    $corpusDir = Join-Path $repoAbs "tmp/parity-corpus"
    if (-not (Test-Path $corpusDir)) {
        New-Item -ItemType Directory -Path $corpusDir -Force | Out-Null
    }

    $out = Join-Path $corpusDir "$Label-corpus.zig"
    $parts = New-Object System.Collections.Generic.List[string]
    $files = Get-ChildItem -Path $item.FullName -Recurse -Filter *.zig -File
    foreach ($f in $files) {
        $raw = Get-Content -Path $f.FullName -Raw
        if ($raw -match 'test\s+"') {
            [void]$parts.Add("// FILE: $($f.FullName)")
            [void]$parts.Add($raw)
            [void]$parts.Add("")
        }
    }

    if ($parts.Count -eq 0) {
        throw "No tests found under directory: $InputPath"
    }

    $parts -join "`n" | Set-Content -Path $out -NoNewline
    return $out
}

$goldenInput = Resolve-CorpusPath -InputPath $goldenAbs -Label "golden"
$candidateInput = Resolve-CorpusPath -InputPath $candidateAbs -Label "candidate"

$args = @(
    "run",
    "--manifest-path", $cargoToml,
    "--bin", "review",
    "--",
    "--test-parity-audit",
    "--golden", $goldenInput,
    "--candidate", $candidateInput,
    "--audit-report", $auditAbs,
    "--target", $repoAbs,
    "--backend", $Backend
)

if ($Mapping -ne "") {
    $mappingAbs = Join-Path $repoAbs $Mapping
    if (-not (Test-Path $mappingAbs)) {
        throw "Mapping file not found: $mappingAbs"
    }
    $args += @("--mapping", $mappingAbs)
}

Write-Host "Running parity audit..."
Write-Host "  golden: $goldenInput"
Write-Host "  candidate: $candidateInput"
Write-Host "  report: $auditAbs"
if ($Mapping -ne "") { Write-Host "  mapping: $mappingAbs" }

& cargo @args
$exit = $LASTEXITCODE
if ($exit -eq 2) {
    Write-Warning "parity audit completed with WARN status (exit code 2). See report: $auditAbs"
    exit 0
}
if ($exit -ne 0) {
    throw "parity audit failed with exit code $exit"
}

Write-Host "wrote audit report: $auditAbs"
