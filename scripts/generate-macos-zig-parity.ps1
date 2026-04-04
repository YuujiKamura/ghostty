param(
    [string]$UpstreamRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "..\ghostty-upstream"),
    [string]$TargetRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

function Split-CamelCase {
    param([string]$s)
    if (-not $s) { return "" }
    $step1 = [regex]::Replace($s, '([a-z0-9])([A-Z])', '$1 $2')
    $step2 = [regex]::Replace($step1, '([A-Z])([A-Z][a-z])', '$1 $2')
    return $step2
}

$StopWords = @(
    'test','tests','ghostty','ui','unit','basic','functionality','case','cases','with','for',
    'and','or','to','from','of','on','in','is','are','be','by','using','like','supports'
)

function Get-Tokens {
    param([string]$s)
    $expanded = Split-CamelCase $s
    $clean = ($expanded -replace '[^A-Za-z0-9]+', ' ').ToLowerInvariant().Trim()
    if (-not $clean) { return @() }
    $tokens = $clean -split '\s+' | Where-Object { $_.Length -ge 2 -and $StopWords -notcontains $_ }
    return @($tokens | Select-Object -Unique)
}

function Get-Normalized {
    param([string]$s)
    $tokens = Get-Tokens $s
    return ($tokens -join ' ')
}

function Score-Match {
    param([string[]]$a, [string[]]$b)
    if ($a.Count -eq 0 -or $b.Count -eq 0) { return 0.0 }
    $setA = [System.Collections.Generic.HashSet[string]]::new([string[]]$a)
    $setB = [System.Collections.Generic.HashSet[string]]::new([string[]]$b)
    $inter = 0
    foreach ($x in $setA) {
        if ($setB.Contains($x)) { $inter++ }
    }
    if ($inter -eq 0) { return 0.0 }
    $union = ($setA.Count + $setB.Count - $inter)
    if ($union -le 0) { return 0.0 }
    return [Math]::Round(($inter / $union), 4)
}

function Extract-MacosTests {
    param([string]$root)
    $out = @()

    $swiftFiles = Get-ChildItem (Join-Path $root 'macos') -Recurse -Filter *.swift |
        Where-Object { $_.FullName -match '[/\\]macos[/\\]Tests[/\\]' -or $_.FullName -match '[/\\]macos[/\\]GhosttyUITests[/\\]' }

    foreach ($f in $swiftFiles) {
        $content = Get-Content $f.FullName
        for ($i = 0; $i -lt $content.Count; $i++) {
            $line = $content[$i]

            if ($line -match '@Test\("([^"]+)"') {
                $name = $Matches[1]
                $tokens = Get-Tokens $name
                $out += [PSCustomObject]@{
                    source = 'macos'
                    suite = if ($f.FullName -match '[/\\]GhosttyUITests[/\\]') { 'ui' } else { 'unit' }
                    file = $f.FullName
                    line = ($i + 1)
                    id = "$($f.BaseName)::${name}"
                    raw_name = $name
                    normalized = (Get-Normalized $name)
                    tokens = ($tokens -join '|')
                }
                continue
            }

            if ($line -match '@Test\b') {
                for ($j = $i; $j -lt [Math]::Min($i + 6, $content.Count); $j++) {
                    if ($content[$j] -match 'func\s+(test[A-Za-z0-9_]+)\s*\(') {
                        $func = $Matches[1]
                        $name = $func
                        $tokens = Get-Tokens $name
                        $out += [PSCustomObject]@{
                            source = 'macos'
                            suite = if ($f.FullName -match '[/\\]GhosttyUITests[/\\]') { 'ui' } else { 'unit' }
                            file = $f.FullName
                            line = ($j + 1)
                            id = "$($f.BaseName)::${func}"
                            raw_name = $name
                            normalized = (Get-Normalized $name)
                            tokens = ($tokens -join '|')
                        }
                        break
                    }
                }
                continue
            }

            if ($f.FullName -match '[/\\]GhosttyUITests[/\\]' -and $line -match '^\s*func\s+(test[A-Za-z0-9_]+)\s*\(') {
                $func = $Matches[1]
                $name = $func
                $tokens = Get-Tokens $name
                $out += [PSCustomObject]@{
                    source = 'macos'
                    suite = 'ui'
                    file = $f.FullName
                    line = ($i + 1)
                    id = "$($f.BaseName)::${func}"
                    raw_name = $name
                    normalized = (Get-Normalized $name)
                    tokens = ($tokens -join '|')
                }
            }
        }
    }

    return $out
}

function Extract-ZigTests {
    param([string]$root, [string]$backend)

    $dir = Join-Path $root "src\\apprt\\$backend"
    if (-not (Test-Path $dir)) { return @() }

    $out = @()
    $files = Get-ChildItem $dir -Recurse -Filter *.zig
    foreach ($f in $files) {
        $content = Get-Content $f.FullName
        for ($i = 0; $i -lt $content.Count; $i++) {
            $line = $content[$i]
            if ($line -match '^\s*test\s+"([^"]+)"') {
                $name = $Matches[1]
                $tokens = Get-Tokens $name
                $out += [PSCustomObject]@{
                    source = $backend
                    suite = 'zig'
                    file = $f.FullName
                    line = ($i + 1)
                    id = "$($f.BaseName)::${name}"
                    raw_name = $name
                    normalized = (Get-Normalized $name)
                    tokens = ($tokens -join '|')
                }
            }
        }
    }

    return $out
}

$macos = Extract-MacosTests -root $UpstreamRoot
$gtk = Extract-ZigTests -root $TargetRoot -backend 'gtk'
$winui3 = Extract-ZigTests -root $TargetRoot -backend 'winui3'

$outDir = Join-Path $TargetRoot 'docs\\test-parity'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$macCsv = Join-Path $outDir 'macos_test_ids.csv'
$zigCsv = Join-Path $outDir 'zig_backend_test_ids.csv'
$parityCsv = Join-Path $outDir 'macos_to_zig_parity.csv'
$reportMd = Join-Path $outDir 'macos_to_zig_parity.md'

$macos | Sort-Object id | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $macCsv
($gtk + $winui3) | Sort-Object source,id | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $zigCsv

$allZig = $gtk + $winui3
$rows = @()

foreach ($m in $macos) {
    $mTokens = @()
    if ($m.tokens) { $mTokens = $m.tokens -split '\|' }

    $bestGtk = $null
    $bestGtkScore = 0.0
    foreach ($z in $gtk) {
        $zTokens = @()
        if ($z.tokens) { $zTokens = $z.tokens -split '\|' }
        $score = Score-Match -a $mTokens -b $zTokens
        if ($score -gt $bestGtkScore) { $bestGtkScore = $score; $bestGtk = $z }
    }

    $bestWin = $null
    $bestWinScore = 0.0
    foreach ($z in $winui3) {
        $zTokens = @()
        if ($z.tokens) { $zTokens = $z.tokens -split '\|' }
        $score = Score-Match -a $mTokens -b $zTokens
        if ($score -gt $bestWinScore) { $bestWinScore = $score; $bestWin = $z }
    }

    $rows += [PSCustomObject]@{
        macos_id = $m.id
        macos_suite = $m.suite
        macos_file = $m.file
        macos_line = $m.line
        macos_name = $m.raw_name
        macos_tokens = $m.tokens
        gtk_best_score = $bestGtkScore
        gtk_best = if ($bestGtk) { $bestGtk.id } else { '' }
        gtk_file = if ($bestGtk) { $bestGtk.file } else { '' }
        gtk_line = if ($bestGtk) { $bestGtk.line } else { '' }
        winui3_best_score = $bestWinScore
        winui3_best = if ($bestWin) { $bestWin.id } else { '' }
        winui3_file = if ($bestWin) { $bestWin.file } else { '' }
        winui3_line = if ($bestWin) { $bestWin.line } else { '' }
    }
}

$rows | Sort-Object macos_id | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $parityCsv

$strongThreshold = 0.50
$weakThreshold = 0.20

$strongGtk = ($rows | Where-Object { [double]$_.gtk_best_score -ge $strongThreshold }).Count
$strongWin = ($rows | Where-Object { [double]$_.winui3_best_score -ge $strongThreshold }).Count
$weakGtk = ($rows | Where-Object { [double]$_.gtk_best_score -ge $weakThreshold -and [double]$_.gtk_best_score -lt $strongThreshold }).Count
$weakWin = ($rows | Where-Object { [double]$_.winui3_best_score -ge $weakThreshold -and [double]$_.winui3_best_score -lt $strongThreshold }).Count
$noneGtk = ($rows | Where-Object { [double]$_.gtk_best_score -lt $weakThreshold }).Count
$noneWin = ($rows | Where-Object { [double]$_.winui3_best_score -lt $weakThreshold }).Count

$topGaps = $rows |
    Sort-Object {[Math]::Max([double]$_.gtk_best_score, [double]$_.winui3_best_score)}, macos_id |
    Select-Object -First 40

$md = @()
$md += '# macOS -> Zig/WinUI Test Parity Report'
$md += ''
$md += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')"
$md += ''
$md += '## Summary'
$md += ''
$md += "- macOS tests discovered: $($macos.Count)"
$md += "- GTK zig tests discovered: $($gtk.Count)"
$md += "- WinUI3 zig tests discovered: $($winui3.Count)"
$md += "- Matching heuristic: token-overlap (Jaccard), not semantic execution parity"
$md += "- Thresholds: strong >= $strongThreshold, weak >= $weakThreshold and < $strongThreshold"
$md += ''
$md += '### macOS -> GTK'
$md += "- strong: $strongGtk"
$md += "- weak: $weakGtk"
$md += "- none: $noneGtk"
$md += ''
$md += '### macOS -> WinUI3'
$md += "- strong: $strongWin"
$md += "- weak: $weakWin"
$md += "- none: $noneWin"
$md += ''
$md += '## Highest-Risk Gaps (lowest overlap first)'
$md += ''
$md += '| macOS test id | best GTK score | best GTK | best WinUI3 score | best WinUI3 |'
$md += '|---|---:|---|---:|---|'
foreach ($r in $topGaps) {
    $md += "| $($r.macos_id) | $($r.gtk_best_score) | $($r.gtk_best) | $($r.winui3_best_score) | $($r.winui3_best) |"
}
$md += ''
$md += '## Artifacts'
$md += ''
$md += '- macOS ID ledger: docs/test-parity/macos_test_ids.csv'
$md += '- Zig test ledger: docs/test-parity/zig_backend_test_ids.csv'
$md += '- Raw parity matrix: docs/test-parity/macos_to_zig_parity.csv'
$md += ''
$md += '## Notes'
$md += ''
$md += '- This report detects likely correspondence by names/tokens only.'
$md += '- Use this as triage input; then build explicit golden IDs mapping for high-confidence parity audits.'

Set-Content -Path $reportMd -Value ($md -join "`r`n") -Encoding UTF8

Write-Output "macOS tests: $($macos.Count)"
Write-Output "GTK tests: $($gtk.Count)"
Write-Output "WinUI3 tests: $($winui3.Count)"
Write-Output "Report: $reportMd"
