#Requires -Version 5.1
<#
.SYNOPSIS
    Verify Zig-native control plane replaced Rust DLL (commit 42297d393, 0a132927d).

.DESCRIPTION
    After the Zig-native CP migration, no Rust DLL references should remain
    in the WinUI3 apprt. The control_plane.zig should be the sole CP implementation.

.NOTES
    Static analysis only. No Ghostty runtime needed.
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

$winui3Dir = Join-Path $RepoRoot "src\apprt\winui3"

# ================================================================
# 1. control_plane.zig exists and is Zig-native
# ================================================================
$cpZig = Join-Path $winui3Dir "control_plane.zig"
Check "control_plane.zig exists" (Test-Path $cpZig) "File not found"

$cpContent = Get-Content $cpZig -Raw
Check "CP is Zig-native (comment marker)" `
    ($cpContent -match 'Zig-native control plane') `
    "Missing 'Zig-native control plane' marker"

# ================================================================
# 2. No Rust DLL loading references in winui3 apprt
# ================================================================
$allZig = Get-ChildItem $winui3Dir -Filter "*.zig" | Where-Object { $_.Name -ne "com_generated.zig" }
$foundRustDll = $false
foreach ($f in $allZig) {
    $c = Get-Content $f.FullName -Raw
    if ($c -match 'LoadLibrary.*rust|rust.*\.dll|control.plane.server\.dll') {
        $foundRustDll = $true
        Write-Host "  Found Rust DLL ref in $($f.Name)" -ForegroundColor Yellow
    }
}
Check "No Rust DLL loading in winui3 apprt" (-not $foundRustDll) `
    "Rust DLL references should be removed after Zig-native CP migration"

# ================================================================
# 3. CP has named pipe communication (not DLL FFI)
# ================================================================
Check "CP uses named pipes" `
    ($cpContent -match 'pipe_prefix|CreateNamedPipe|named.pipe') `
    "Zig-native CP should use named pipes for IPC"

# ================================================================
# 4. CP has session management
# ================================================================
Check "CP has session management" `
    ($cpContent -match 'session_name|session.*id') `
    "CP should manage sessions"

# ================================================================
# 5. No extern "C" fn declarations for Rust FFI in CP
# ================================================================
Check "No Rust FFI extern declarations in CP" `
    (-not ($cpContent -match 'extern\s+"C"\s+fn\s+cp_')) `
    "Should not have extern C function declarations for Rust CP"

# ================================================================
# Summary
# ================================================================
Write-Host "`n--- Summary: $pass passed, $fail failed ---"
if ($fail -gt 0) { exit 1 }
