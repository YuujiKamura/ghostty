param(
    [string]$RepoRoot = "C:\Users\yuuji\ghostty-win",
    [string]$WindowsRsRoot = "C:\Users\yuuji\winrt-projection-refs\windows-rs",
    [int]$MaxCases = 200,
    [switch]$RequireComplete
)

$ErrorActionPreference = "Stop"

$goldenDir = Join-Path $RepoRoot "tools\winmd2zig\shadow\windows-rs\bindgen-golden"
$winmdDir = Join-Path $WindowsRsRoot "crates\libs\bindgen\default"
$winmdPath = Join-Path $winmdDir "Windows.winmd"
$toolDir = Join-Path $RepoRoot "tools\winmd2zig"

if (-not (Test-Path -LiteralPath $goldenDir)) { throw "missing: $goldenDir" }
if (-not (Test-Path -LiteralPath $winmdPath)) { throw "missing: $winmdPath" }
if (-not (Test-Path -LiteralPath $winmdDir)) { throw "missing: $winmdDir" }

$winmdCandidates = @($winmdPath)
$others = Get-ChildItem -LiteralPath $winmdDir -File -Filter *.winmd | Where-Object { $_.FullName -ne $winmdPath } | Sort-Object Name
foreach ($f in $others) { $winmdCandidates += $f.FullName }

function Get-ActualGuid([string]$outText) {
    $m = [regex]::Match($outText, "pub const IID = GUID\{[\s\S]*?\.Data1 = 0x([0-9a-fA-F]{8}), \.Data2 = 0x([0-9a-fA-F]{4}), \.Data3 = 0x([0-9a-fA-F]{4}),[\s\S]*?\.Data4 = \.\{ ([0-9a-fA-Fx,\s]+) \}")
    if (-not $m.Success) { return $null }
    $d1 = $m.Groups[1].Value.ToLowerInvariant()
    $d2 = $m.Groups[2].Value.ToLowerInvariant()
    $d3 = $m.Groups[3].Value.ToLowerInvariant()
    $bytes = $m.Groups[4].Value.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" } | ForEach-Object { ($_ -replace "^0x","").ToLowerInvariant() }
    if ($bytes.Count -ne 8) { return $null }
    return "{0}-{1}-{2}-{3}{4}-{5}{6}{7}{8}{9}{10}" -f $d1,$d2,$d3,$bytes[0],$bytes[1],$bytes[2],$bytes[3],$bytes[4],$bytes[5],$bytes[6],$bytes[7]
}

$pattern = [regex]'define_interface!\(\s*([A-Za-z0-9_]+)\s*,\s*[A-Za-z0-9_]+\s*,\s*0x([0-9a-fA-F_]{32,40})'
$rtPattern = [regex]'(?s)impl windows_core::RuntimeName for ([A-Za-z0-9_]+)\s*\{\s*const NAME: &''static str = "([^"]+)";'
$pairs = @{}

Get-ChildItem -LiteralPath $goldenDir -File -Filter *.rs | ForEach-Object {
    $text = Get-Content -Raw -LiteralPath $_.FullName
    $runtimeNames = @{}
    foreach ($rm in $rtPattern.Matches($text)) {
        $runtimeNames[$rm.Groups[1].Value] = $rm.Groups[2].Value
    }
    $ms = $pattern.Matches($text)
    foreach ($m in $ms) {
        $name = $m.Groups[1].Value
        $hex = ($m.Groups[2].Value -replace "_", "").ToLowerInvariant()
        if ($hex.Length -ne 32) { continue }
        $guid = "{0}-{1}-{2}-{3}-{4}" -f $hex.Substring(0,8),$hex.Substring(8,4),$hex.Substring(12,4),$hex.Substring(16,4),$hex.Substring(20,12)
        if (-not $pairs.ContainsKey($name)) {
            $pairs[$name] = [pscustomobject]@{
                expected = $guid
                symbol = $name
                full_name = $(if ($runtimeNames.ContainsKey($name)) { $runtimeNames[$name] } else { $name })
            }
        }
    }
}

$targets = $pairs.GetEnumerator() | Sort-Object Name | Select-Object -First $MaxCases
if ($targets.Count -eq 0) { throw "no interface pairs extracted" }

$ok = 0
$fail = 0
$skip = 0
$fails = @()
$skips = @()

Push-Location $toolDir
try {
    foreach ($kv in $targets) {
        $name = $kv.Name
        $expected = $kv.Value.expected
        $fullName = $kv.Value.full_name
        $resolvedName = $fullName

        $out = $null
        $resolved = $false
        foreach ($w in $winmdCandidates) {
            $out = & zig build run -- $w $resolvedName 2>$null
            if ($LASTEXITCODE -eq 0) {
                $resolved = $true
                break
            }
        }

        # If unresolved and we only had a short symbol, try resolving full names from TypeDef.
        if (-not $resolved -and ($resolvedName -notmatch "\.")) {
            $cands = @()
            foreach ($w in $winmdCandidates) {
                $found = & zig build run -- --find-type $w $resolvedName 2>$null
                if ($LASTEXITCODE -ne 0) { continue }
                foreach ($line in ($found -split "`r?`n")) {
                    $v = $line.Trim()
                    if (-not $v -or $v -eq "(none)") { continue }
                    $cands += [pscustomobject]@{ winmd = $w; full = $v }
                }
            }
            $cands = $cands | Sort-Object full -Unique
            if ($cands.Count -ge 1) {
                foreach ($c in $cands) {
                    $candidateOut = & zig build run -- $c.winmd $c.full 2>$null
                    if ($LASTEXITCODE -ne 0) { continue }
                    $candidateGuid = Get-ActualGuid $candidateOut
                    if ($candidateGuid -and ($candidateGuid -eq $expected)) {
                        $resolvedName = $c.full
                        $out = $candidateOut
                        $resolved = $true
                        break
                    }
                }
            }
        }

        if (-not $resolved) {
            $skip++
            $skips += $fullName
            continue
        }

        $actual = Get-ActualGuid $out
        if (-not $actual) {
            $fail++
            $fails += "parse-fail $name"
            continue
        }

        if ($actual -eq $expected) {
            $ok++
        } else {
            $fail++
            $fails += "$name expected=$expected actual=$actual"
        }
    }
}
finally {
    Pop-Location
}

Write-Host "winmd2zig iid shadow: ok=$ok fail=$fail skip=$skip total=$($targets.Count)"
if ($fails.Count -gt 0) {
    $fails | Select-Object -First 30 | ForEach-Object { Write-Host $_ }
}
if ($skips.Count -gt 0) {
    Write-Host "skipped examples:"
    $skips | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
}

if ($fail -gt 0) {
    throw "winmd2zig iid shadow failed"
}
if ($RequireComplete -and $skip -gt 0) {
    throw "winmd2zig iid shadow incomplete (skip=$skip)"
}
