param(
    [string]$RepoRoot = ".",
    [string]$GoldenDir = "src/apprt/gtk",
    [string]$CandidateDir = "src/apprt/winui3",
    [string]$OutFile = "tmp/winui3-test-parity.md"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-TestNames {
    param([string]$Dir)

    $root = Resolve-Path $RepoRoot
    $target = Join-Path $root $Dir
    if (-not (Test-Path $target)) {
        throw "Directory not found: $Dir"
    }

    $names = New-Object System.Collections.Generic.List[string]
    $zigFiles = Get-ChildItem -Path $target -Recurse -Filter *.zig -File
    foreach ($f in $zigFiles) {
        $content = Get-Content -Path $f.FullName -Raw
        $ms = [regex]::Matches($content, 'test\s+"([^"]+)"')
        foreach ($m in $ms) {
            [void]$names.Add($m.Groups[1].Value.Trim())
        }
    }
    return $names | Sort-Object -Unique
}

function Norm([string]$s) {
    return ($s.ToLowerInvariant() -replace '[^a-z0-9]+', ' ').Trim()
}

$golden = Get-TestNames -Dir $GoldenDir
$candidate = Get-TestNames -Dir $CandidateDir

$goldenNorm = @{}
foreach ($g in $golden) { $goldenNorm[(Norm $g)] = $g }
$candNorm = @{}
foreach ($c in $candidate) { $candNorm[(Norm $c)] = $c }

$matched = New-Object System.Collections.Generic.List[object]
$missing = New-Object System.Collections.Generic.List[string]
$extra = New-Object System.Collections.Generic.List[string]

foreach ($k in $goldenNorm.Keys) {
    if ($candNorm.ContainsKey($k)) {
        [void]$matched.Add([pscustomobject]@{
            Golden = $goldenNorm[$k]
            Candidate = $candNorm[$k]
        })
    } else {
        [void]$missing.Add($goldenNorm[$k])
    }
}

foreach ($k in $candNorm.Keys) {
    if (-not $goldenNorm.ContainsKey($k)) {
        [void]$extra.Add($candNorm[$k])
    }
}

$total = $golden.Count
$covered = $matched.Count
$ratio = if ($total -eq 0) { 0 } else { [math]::Round(($covered / $total) * 100, 1) }

$lines = New-Object System.Collections.Generic.List[string]
[void]$lines.Add("# WinUI3 Test Parity Report")
[void]$lines.Add("")
[void]$lines.Add("- Golden: $GoldenDir")
[void]$lines.Add("- Candidate: $CandidateDir")
[void]$lines.Add("- Golden tests: $total")
[void]$lines.Add("- Matched (normalized name): $covered")
[void]$lines.Add("- Coverage: $ratio%")
[void]$lines.Add("- Missing in candidate: $($missing.Count)")
[void]$lines.Add("- Extra in candidate: $($extra.Count)")
[void]$lines.Add("")

[void]$lines.Add("## Missing In Candidate")
if ($missing.Count -eq 0) {
    [void]$lines.Add("- (none)")
} else {
    foreach ($m in ($missing | Sort-Object)) {
        [void]$lines.Add("- $m")
    }
}
[void]$lines.Add("")

[void]$lines.Add("## Extra In Candidate")
if ($extra.Count -eq 0) {
    [void]$lines.Add("- (none)")
} else {
    foreach ($e in ($extra | Sort-Object)) {
        [void]$lines.Add("- $e")
    }
}
[void]$lines.Add("")

[void]$lines.Add("## Matched Pairs")
if ($matched.Count -eq 0) {
    [void]$lines.Add("- (none)")
} else {
    foreach ($m in ($matched | Sort-Object Golden)) {
        [void]$lines.Add("- `"$($m.Golden)`" -> `"$($m.Candidate)`"")
    }
}

$outAbs = Join-Path (Resolve-Path $RepoRoot) $OutFile
$outDir = Split-Path -Parent $outAbs
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

$lines -join "`n" | Set-Content -Path $outAbs -NoNewline
Write-Host "wrote parity report: $outAbs"
