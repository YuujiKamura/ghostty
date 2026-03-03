param(
    [string]$RepoRoot = "C:\Users\yuuji\ghostty-win",
    [string]$WindowsRsRoot = "C:\Users\yuuji\winrt-projection-refs\windows-rs",
    [switch]$Check
)

$ErrorActionPreference = "Stop"

$toolBindgenMain = Join-Path $WindowsRsRoot "crates\tools\bindgen\src\main.rs"
$bindgenGoldenSrc = Join-Path $WindowsRsRoot "crates\tests\libs\bindgen\src"
$outRoot = Join-Path $RepoRoot "tools\winmd2zig\shadow\windows-rs"
$outCases = Join-Path $outRoot "bindgen-cases.json"
$outGolden = Join-Path $outRoot "bindgen-golden"

if (-not (Test-Path -LiteralPath $toolBindgenMain)) { throw "missing: $toolBindgenMain" }
if (-not (Test-Path -LiteralPath $bindgenGoldenSrc)) { throw "missing: $bindgenGoldenSrc" }

$null = New-Item -ItemType Directory -Force -Path $outRoot

$text = Get-Content -Raw -LiteralPath $toolBindgenMain
$regex = [regex]'(?ms)\b(test|test_raw|bindgen)\(\s*"([^"]+)"'
$matches = $regex.Matches($text)

$cases = @()
$i = 0
foreach ($m in $matches) {
    $i++
    $cases += [pscustomobject]@{
        id = "{0:000}" -f $i
        kind = $m.Groups[1].Value
        args = $m.Groups[2].Value
    }
}

$json = $cases | ConvertTo-Json -Depth 4
$jsonNormalized = ($cases | ConvertTo-Json -Depth 4 -Compress)

if ($Check) {
    $ok = $true
    if (-not (Test-Path -LiteralPath $outCases)) {
        Write-Host "MISSING: $outCases"
        $ok = $false
    } else {
        $old = Get-Content -Raw -LiteralPath $outCases
        $oldNormalized = ((ConvertFrom-Json -InputObject $old) | ConvertTo-Json -Depth 4 -Compress)
        if ($oldNormalized -ne $jsonNormalized) {
            Write-Host "DIFF: $outCases"
            $ok = $false
        }
    }

    if (-not (Test-Path -LiteralPath $outGolden)) {
        Write-Host "MISSING: $outGolden"
        $ok = $false
    } else {
        $srcCount = (Get-ChildItem -LiteralPath $bindgenGoldenSrc -File -Filter *.rs).Count
        $dstCount = (Get-ChildItem -LiteralPath $outGolden -File -Filter *.rs).Count
        if ($srcCount -ne $dstCount) {
            Write-Host "DIFF: golden count src=$srcCount dst=$dstCount"
            $ok = $false
        }
    }

    if (-not $ok) { exit 2 }
    Write-Host "windows-rs shadow: OK"
    exit 0
}

$json | Set-Content -LiteralPath $outCases -Encoding UTF8

if (Test-Path -LiteralPath $outGolden) {
    Remove-Item -Recurse -Force -LiteralPath $outGolden
}
Copy-Item -Recurse -Force -LiteralPath $bindgenGoldenSrc -Destination $outGolden

Write-Host "wrote: $outCases"
Write-Host "mirrored golden: $outGolden"
Write-Host "cases: $($cases.Count)"
