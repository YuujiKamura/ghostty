#Requires -Version 5.1
<#
.SYNOPSIS
    Verify HLSL bg_color blend simplification (commit 56859a505).

.DESCRIPTION
    The bg_color blend in cell_text.vs.hlsl was simplified to use
    alpha-based blending with global_bg. Verify the pattern exists
    and no redundant blend code remains.

.NOTES
    Static analysis only.
#>

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$pass = 0
$fail = 0

function Check([string]$Name, [bool]$Condition, [string]$Detail) {
    if ($Condition) {
        Write-Host "[PASS] $Name" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "[FAIL] $Name -- $Detail" -ForegroundColor Red
        $script:fail++
    }
}

$vsHlsl = Join-Path $RepoRoot "src\renderer\shaders\hlsl\cell_text.vs.hlsl"
Check "cell_text.vs.hlsl exists" (Test-Path $vsHlsl) "Shader not found"

$content = Get-Content $vsHlsl -Raw

# ================================================================
# 1. bg_color uses alpha blend with global_bg
# ================================================================
Check "bg_color alpha blend with global_bg" `
    ($content -match 'bg_color.*global_bg.*\(1\.0\s*-.*\.a\)' -or
     $content -match 'global_bg.*\(1\.0\s*-.*bg_color\.a\)') `
    "Should blend bg_color with global_bg using alpha: bg + global_bg * (1 - alpha)"

# ================================================================
# 2. bg_color is assigned from load_color
# ================================================================
Check "bg_color assigned from load_color or unpack" `
    ($content -match 'bg_color\s*=\s*load_color' -or
     $content -match 'bg_color\s*=.*unpack4u8') `
    "bg_color should be loaded from packed cell data"

# ================================================================
# 3. No duplicate blend operations
# ================================================================
$blendCount = ([regex]::Matches($content, 'bg_color.*global_bg')).Count
Check "Single bg_color/global_bg blend" `
    ($blendCount -le 2) `
    "Should have at most 2 bg_color/global_bg references (assign + blend), found $blendCount"

# ================================================================
# Summary
# ================================================================
Write-Host "`n--- Summary: $pass passed, $fail failed ---"
if ($fail -gt 0) { exit 1 }
