#Requires -Version 5.1
<#
.SYNOPSIS
    Regression test for commit 3cc65ef47: removal of CPU-side cursor color override.

.DESCRIPTION
    Verifies that src/renderer/generic.zig does NOT contain CPU-side cursor
    color override code that was removed in #133. The removed code:
    1. Directly mutated fg_rows cell colors at cursor position
    2. Tracked cursor_color_override_row for blink-off restoration
    3. Caused first-char hiding after eraseLine sequences

    The HLSL shader (cell_text.vs.hlsl) handles cursor text color inversion
    correctly; the CPU-side override was redundant and harmful.

.NOTES
    Static analysis only. Checks for absence of removed patterns.
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

$GenericZig = Join-Path $RepoRoot "src\renderer\generic.zig"
Check "generic.zig exists" (Test-Path $GenericZig) "File not found: $GenericZig"

$content = Get-Content $GenericZig -Raw

# ================================================================
# 1. cursor_color_override_row field must NOT exist
# ================================================================
Check "No cursor_color_override_row field" `
    (-not ($content -match 'cursor_color_override_row')) `
    "Found cursor_color_override_row -- removed in 3cc65ef47"

# ================================================================
# 2. No direct mutation of fg_rows item.color at cursor position
# ================================================================
Check "No fg_rows cursor color mutation" `
    (-not ($content -match 'fg_rows\.lists\[.*\]\.items.*\.color\s*=')) `
    "Found fg_rows item.color assignment -- CPU-side cursor override should be removed"

# ================================================================
# 3. No pattern: item.color = { uniform_color.r, ... } in cursor block
# ================================================================
Check "No item.color = uniform_color pattern" `
    (-not ($content -match 'item\.color\s*=\s*\.{')) `
    "Found item.color struct literal assignment -- likely cursor override remnant"

# ================================================================
# 4. No cursor_color_override_row maxInt sentinel pattern
# ================================================================
Check "No maxInt sentinel for cursor override" `
    (-not ($content -match 'cursor_color_override.*maxInt')) `
    "Found maxInt sentinel for cursor color override tracking"

# ================================================================
# 5. No rebuildRow call guarded by cursor_color_override
# ================================================================
Check "No cursor-override-guarded rebuildRow" `
    (-not ($content -match 'cursor_color_override.*rebuildRow')) `
    "Found rebuildRow call associated with cursor color override restoration"

# ================================================================
# 6. Shader-based cursor inversion still present in HLSL
# ================================================================
$ShaderPath = Join-Path $RepoRoot "src\renderer\shaders\cell_text.vs.hlsl"
if (Test-Path $ShaderPath) {
    $shaderContent = Get-Content $ShaderPath -Raw
    Check "Shader cursor inversion exists" `
        ($shaderContent -match 'cursor_color|cursor_pos') `
        "HLSL shader should contain cursor color/pos uniforms for GPU-side inversion"
} else {
    # D3D11 backend may use different shader path
    Write-Host "[SKIP] HLSL shader not at expected path" -ForegroundColor Yellow
}

# ================================================================
# 7. Verify cursor uniform_color assignment still exists (the shader input)
# ================================================================
Check "cursor uniform_color assignment exists" `
    ($content -match 'uniform_color\.(r|g|b)') `
    "uniform_color should still be set for shader-based cursor rendering"

# ================================================================
# Summary
# ================================================================
Write-Host "`n--- Summary: $pass passed, $fail failed ---"
if ($fail -gt 0) { exit 1 }
