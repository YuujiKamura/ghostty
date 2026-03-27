#Requires -Version 5.1
<#
.SYNOPSIS
    Verify block cursor renders inverted character via D3D11 shader (#130).

.DESCRIPTION
    After commits e3933974f and c17caa359, cursor text color inversion is handled
    entirely in the HLSL vertex shader (cell_text.vs.hlsl), not CPU-side.
    The shader must have cursor_pos, cursor_color uniforms and IS_CURSOR_GLYPH logic.

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

# ================================================================
# HLSL vertex shader: cursor inversion logic
# ================================================================
$shaderDir = Join-Path $RepoRoot "src\renderer\shaders\hlsl"
$vsHlsl = Join-Path $shaderDir "cell_text.vs.hlsl"
Check "cell_text.vs.hlsl exists" (Test-Path $vsHlsl) "Shader not found"

$vsContent = Get-Content $vsHlsl -Raw

# cursor_pos unpacking from uniform
Check "Shader unpacks cursor_pos" `
    ($vsContent -match 'cursor_pos.*unpack2u16') `
    "Should unpack cursor position from packed uniform"

# cursor_color unpacking
Check "Shader unpacks cursor_color" `
    ($vsContent -match 'cursor_color_packed_4u8') `
    "Should reference cursor_color_packed_4u8 uniform"

# is_cursor_pos calculation
Check "Shader calculates is_cursor_pos" `
    ($vsContent -match 'is_cursor_pos') `
    "Should determine if current cell is at cursor position"

# IS_CURSOR_GLYPH flag check
Check "Shader checks IS_CURSOR_GLYPH" `
    ($vsContent -match 'IS_CURSOR_GLYPH') `
    "Should check IS_CURSOR_GLYPH flag for cursor glyph vs text glyph"

# cursor_wide support
Check "Shader handles cursor_wide" `
    ($vsContent -match 'cursor_wide') `
    "Should handle wide cursor (CJK characters)"

# Color inversion at cursor position
Check "Shader inverts color at cursor" `
    ($vsContent -match 'is_cursor_pos.*\{' -or $vsContent -match 'if.*is_cursor_pos') `
    "Should branch on is_cursor_pos to invert text color"

# ================================================================
# common.hlsl: cursor uniforms defined
# ================================================================
$commonHlsl = Join-Path $shaderDir "common.hlsl"
if (Test-Path $commonHlsl) {
    $commonContent = Get-Content $commonHlsl -Raw
    Check "common.hlsl defines cursor_pos_packed" `
        ($commonContent -match 'cursor_pos_packed_2u16') `
        "Should define cursor_pos_packed_2u16 in uniform buffer"
    Check "common.hlsl defines cursor_color_packed" `
        ($commonContent -match 'cursor_color_packed_4u8') `
        "Should define cursor_color_packed_4u8 in uniform buffer"
} else {
    Write-Host "[SKIP] common.hlsl not found" -ForegroundColor Yellow
}

# ================================================================
# Summary
# ================================================================
Write-Host "`n--- Summary: $pass passed, $fail failed ---"
if ($fail -gt 0) { exit 1 }
