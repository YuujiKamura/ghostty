param(
    [string]$RepoRoot = "C:\Users\yuuji\ghostty-win",
    [string]$WindowsRsRoot = "C:\Users\yuuji\winrt-projection-refs\windows-rs"
)

$ErrorActionPreference = "Stop"

$shadowGolden = Join-Path $RepoRoot "tools\winmd2zig\shadow\windows-rs\bindgen-golden"
$refGenerated = Join-Path $WindowsRsRoot "crates\tests\libs\bindgen\src"

if (-not (Test-Path -LiteralPath $shadowGolden)) {
    throw "shadow golden not found: $shadowGolden"
}
if (-not (Test-Path -LiteralPath $refGenerated)) {
    throw "windows-rs bindgen src not found: $refGenerated"
}

Push-Location $WindowsRsRoot
try {
    cargo run -p tool_bindgen | Out-Null
}
finally {
    Pop-Location
}

$refFiles = Get-ChildItem -LiteralPath $refGenerated -File -Filter *.rs | Sort-Object Name
$shadowFiles = Get-ChildItem -LiteralPath $shadowGolden -File -Filter *.rs | Sort-Object Name

if ($refFiles.Count -ne $shadowFiles.Count) {
    throw "file count mismatch: ref=$($refFiles.Count) shadow=$($shadowFiles.Count)"
}

$refMap = @{}
foreach ($f in $refFiles) { $refMap[$f.Name] = $f.FullName }
$shadowMap = @{}
foreach ($f in $shadowFiles) { $shadowMap[$f.Name] = $f.FullName }

$mismatches = @()
foreach ($name in $refMap.Keys | Sort-Object) {
    if (-not $shadowMap.ContainsKey($name)) {
        $mismatches += "missing in shadow: $name"
        continue
    }
    $a = Get-Content -Raw -LiteralPath $refMap[$name]
    $b = Get-Content -Raw -LiteralPath $shadowMap[$name]
    if ($a -ne $b) {
        $mismatches += "content mismatch: $name"
    }
}

if ($mismatches.Count -gt 0) {
    $mismatches | ForEach-Object { Write-Host $_ }
    throw "windows-rs shadow ref test failed ($($mismatches.Count) mismatches)"
}

Write-Host "windows-rs shadow ref test: OK ($($refFiles.Count) files)"
