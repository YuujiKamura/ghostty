#Requires -Version 5.1
<#
.SYNOPSIS
    Test for lefthook pre-commit hooks configuration (commit 063193f5a).

.DESCRIPTION
    Verifies the lefthook.yml configuration:
    1. File exists at repo root
    2. Has pre-commit section with zig-fmt and vtable-manifest commands
    3. zig-fmt uses --check flag (non-destructive)
    4. zig-fmt targets .zig files via glob
    5. vtable-manifest runs build-winui3.sh
    6. Has pre-push section with build-check command
    7. vtable-manifest skips merge and rebase

.NOTES
    Static analysis only. Does not run lefthook.
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

$lefthookPath = Join-Path $RepoRoot "lefthook.yml"

# 1. File exists
Check "lefthook.yml exists" `
    (Test-Path $lefthookPath) `
    "lefthook.yml not found at repo root"

if (-not (Test-Path $lefthookPath)) {
    Write-Host ""
    Write-Host "lefthook config test: $pass PASS / $fail FAIL" -ForegroundColor Red
    exit $fail
}

$content = Get-Content $lefthookPath -Raw

# 2. Has pre-commit section
Check "lefthook: pre-commit section exists" `
    ($content -match 'pre-commit:') `
    "Should have pre-commit section"

# 3. Has zig-fmt command
Check "lefthook: zig-fmt command exists" `
    ($content -match 'zig-fmt:') `
    "Should have zig-fmt pre-commit command"

# 4. zig-fmt uses --check (non-destructive)
Check "lefthook: zig-fmt uses --check" `
    ($content -match 'zig fmt --check') `
    "zig-fmt should use --check flag to avoid modifying files"

# 5. zig-fmt targets .zig files
Check "lefthook: zig-fmt targets *.zig" `
    ($content -match 'glob:.*\*\.zig') `
    "zig-fmt should target *.zig files"

# 6. vtable-manifest command exists
Check "lefthook: vtable-manifest command exists" `
    ($content -match 'vtable-manifest:') `
    "Should have vtable-manifest pre-commit command"

# 7. vtable-manifest runs build-winui3.sh
Check "lefthook: vtable-manifest runs build script" `
    ($content -match 'build-winui3\.sh') `
    "vtable-manifest should run build-winui3.sh"

# 8. Has pre-push section
Check "lefthook: pre-push section exists" `
    ($content -match 'pre-push:') `
    "Should have pre-push section"

# 9. pre-push has build-check
Check "lefthook: pre-push build-check command" `
    ($content -match 'build-check:') `
    "Should have build-check pre-push command"

# 10. vtable-manifest skips merge/rebase
Check "lefthook: vtable-manifest skips merge" `
    ($content -match 'skip:[\s\S]*?- merge') `
    "vtable-manifest should skip on merge"

Check "lefthook: vtable-manifest skips rebase" `
    ($content -match 'skip:[\s\S]*?- rebase') `
    "vtable-manifest should skip on rebase"

# 11. parallel is enabled for pre-commit
Check "lefthook: pre-commit parallel enabled" `
    ($content -match 'parallel:\s*true') `
    "pre-commit hooks should run in parallel"

# Summary
Write-Host ""
Write-Host "lefthook config test: $pass PASS / $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
exit $fail
