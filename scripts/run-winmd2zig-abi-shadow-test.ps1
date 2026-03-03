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

function Split-TopLevelArgs([string]$argList) {
    $text = $argList.Trim()
    if (-not $text) { return @() }
    $parts = @()
    $cur = New-Object System.Text.StringBuilder
    $depthParen = 0
    $depthAngle = 0
    foreach ($ch in $text.ToCharArray()) {
        if ($ch -eq '(') { $depthParen++ }
        elseif ($ch -eq ')') { if ($depthParen -gt 0) { $depthParen-- } }
        elseif ($ch -eq '<') { $depthAngle++ }
        elseif ($ch -eq '>') { if ($depthAngle -gt 0) { $depthAngle-- } }

        if ($ch -eq ',' -and $depthParen -eq 0 -and $depthAngle -eq 0) {
            $parts += $cur.ToString().Trim()
            $null = $cur.Clear()
            continue
        }
        $null = $cur.Append($ch)
    }
    $tail = $cur.ToString().Trim()
    if ($tail) { $parts += $tail }
    return $parts
}

function Get-RsVtableMethods([string]$symbol, [string]$goldenDirectory) {
    $files = Get-ChildItem -LiteralPath $goldenDirectory -File -Filter *.rs
    $best = $null
    $bestScoreKnown = -1
    $bestScoreSlots = -1
    foreach ($f in $files) {
        $text = Get-Content -Raw -LiteralPath $f.FullName
        $startRe = [regex]("(?:pub\s+)?struct\s+" + [regex]::Escape($symbol) + "_Vtbl\s*\{")
        $m = $startRe.Match($text)
        if (-not $m.Success) { continue }
        $braceStart = $text.IndexOf('{', $m.Index)
        if ($braceStart -lt 0) { continue }
        $depth = 1
        $i = $braceStart + 1
        while ($i -lt $text.Length -and $depth -gt 0) {
            $ch = $text[$i]
            if ($ch -eq '{') { $depth++ }
            elseif ($ch -eq '}') { $depth-- }
            $i++
        }
        if ($depth -ne 0) { continue }
        $body = $text.Substring($braceStart + 1, ($i - $braceStart - 2))

        $fields = @()
        $cur = New-Object System.Text.StringBuilder
        $depthParen = 0
        $depthAngle = 0
        foreach ($ch in $body.ToCharArray()) {
            if ($ch -eq '(') { $depthParen++ }
            elseif ($ch -eq ')') { if ($depthParen -gt 0) { $depthParen-- } }
            elseif ($ch -eq '<') { $depthAngle++ }
            elseif ($ch -eq '>') { if ($depthAngle -gt 0) { $depthAngle-- } }

            if ($ch -eq ',' -and $depthParen -eq 0 -and $depthAngle -eq 0) {
                $entry = $cur.ToString().Trim()
                if ($entry) { $fields += $entry }
                $null = $cur.Clear()
                continue
            }
            $null = $cur.Append($ch)
        }
        $tail = $cur.ToString().Trim()
        if ($tail) { $fields += $tail }

        $slots = @()
        $known = 0
        foreach ($field in $fields) {
            $fm = [regex]::Match($field, '^\s*(?:pub\s+)?([A-Za-z0-9_]+)\s*:\s*(.+)\s*$', [System.Text.RegularExpressions.RegexOptions]::Singleline)
            if (-not $fm.Success) { continue }
            $name = $fm.Groups[1].Value
            $typeExpr = $fm.Groups[2].Value.Trim()
            if ($name -eq "base__") { continue }
            $argc = -1
            $fnm = [regex]::Match($typeExpr, 'unsafe extern "system" fn\((.*)\)\s*->', [System.Text.RegularExpressions.RegexOptions]::Singleline)
            if ($fnm.Success) {
                $argc = (Split-TopLevelArgs $fnm.Groups[1].Value).Count
                $known++
            }
            $slots += [pscustomobject]@{
                name = $name
                argc = $argc
            }
        }

        if ($known -gt $bestScoreKnown -or ($known -eq $bestScoreKnown -and $slots.Count -gt $bestScoreSlots)) {
            $best = $slots
            $bestScoreKnown = $known
            $bestScoreSlots = $slots.Count
        }
    }
    if ($null -eq $best) {
        return [pscustomobject]@{
            found = $false
            slots = @()
        }
    }
    return [pscustomobject]@{
        found = $true
        slots = $best
    }
}

function Normalize-RsMethodName([string]$name) {
    return ($name -replace "^(Get|Put|Set|Add|Remove)", "")
}

function Normalize-ZigMethodName([string]$name) {
    $n = ($name -replace "_\d+$", "")
    $n = ($n -replace "^(get_|put_|add_|remove_)", "")
    $n = ($n -replace "^(Get|Put|Set|Add|Remove)", "")
    return $n
}

function Get-ZigVtableMethods([string]$outText) {
    $re = [regex]'(?m)^\s*([A-Za-z0-9_]+):\s*(.+?),\s*//\s*(\d+)\s*$'
    $ms = $re.Matches($outText)
    if ($ms.Count -eq 0) { return @() }
    $items = @()
    foreach ($m in $ms) {
        $name = $m.Groups[1].Value
        $typeExpr = $m.Groups[2].Value.Trim()
        $slot = [int]$m.Groups[3].Value
        $argc = -1
        $fnm = [regex]::Match($typeExpr, '^\*const fn \((.*)\) callconv')
        if ($fnm.Success) {
            $argc = (Split-TopLevelArgs $fnm.Groups[1].Value).Count
        }
        $items += [pscustomobject]@{
            name = $name
            argc = $argc
            slot = $slot
            type = $typeExpr
        }
    }
    $items = $items | Sort-Object slot
    return $items
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
        $symbol = $kv.Name
        $expected = $kv.Value.expected
        $fullName = $kv.Value.full_name
        $resolvedName = $fullName

        $out = $null
        $resolved = $false
        foreach ($w in $winmdCandidates) {
            $out = (& zig build run -- $w $resolvedName 2>$null | Out-String)
            if ($LASTEXITCODE -eq 0) {
                $resolved = $true
                break
            }
        }

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
                    $candidateOut = (& zig build run -- $c.winmd $c.full 2>$null | Out-String)
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
            $skips += "$symbol ($fullName)"
            continue
        }

        $rsInfo = Get-RsVtableMethods -symbol $symbol -goldenDirectory $goldenDir
        if (-not $rsInfo.found) {
            $skip++
            $skips += "$symbol (missing rs vtbl)"
            continue
        }
        $rsMethods = $rsInfo.slots
        $zigMethods = Get-ZigVtableMethods -outText $out
        if ($zigMethods.Count -eq 0 -and $rsMethods.Count -gt 0) {
            $fail++
            $fails += "$symbol no zig methods parsed"
            continue
        }

        $caseFailed = $false
        if ($rsMethods.Count -ne $zigMethods.Count) {
            $caseFailed = $true
            $fails += "$symbol method-count rs=$($rsMethods.Count) zig=$($zigMethods.Count)"
        } else {
            for ($i = 0; $i -lt $rsMethods.Count; $i++) {
                $rsName = Normalize-RsMethodName $rsMethods[$i].name
                $zigName = Normalize-ZigMethodName $zigMethods[$i].name
                if ($rsName -ne $zigName) {
                    $caseFailed = $true
                    $fails += "$symbol method[$i] name rs=$rsName zig=$($zigMethods[$i].name)"
                    break
                }
                if ($rsMethods[$i].argc -ge 0 -and $rsMethods[$i].argc -ne $zigMethods[$i].argc) {
                    $caseFailed = $true
                    $fails += "$symbol method[$i] argc rs=$($rsMethods[$i].argc) zig=$($zigMethods[$i].argc) name=$rsName"
                    break
                }
            }
        }

        if ($caseFailed) {
            $fail++
        } else {
            $ok++
        }
    }
}
finally {
    Pop-Location
}

Write-Host "winmd2zig abi shadow: ok=$ok fail=$fail skip=$skip total=$($targets.Count)"
if ($fails.Count -gt 0) {
    $fails | Select-Object -First 40 | ForEach-Object { Write-Host $_ }
}
if ($skips.Count -gt 0) {
    Write-Host "skipped examples:"
    $skips | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
}

if ($fail -gt 0) {
    throw "winmd2zig abi shadow failed"
}
if ($RequireComplete -and $skip -gt 0) {
    throw "winmd2zig abi shadow incomplete (skip=$skip)"
}
