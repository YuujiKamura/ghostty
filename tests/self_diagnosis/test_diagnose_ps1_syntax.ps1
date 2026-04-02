#Requires -Version 5.1
<#
.SYNOPSIS
    Test for diagnose.ps1 $Pid rename fix (commit 7641780c9).

.DESCRIPTION
    PowerShell's $PID is a read-only automatic variable. Using it as a
    function parameter causes "VariableNotWritable" error under strict mode.
    The fix renamed $Pid to $ProcessId.

    This test verifies:
    1. diagnose.ps1 parses without syntax errors
    2. No function parameter named $Pid (case-insensitive) exists
    3. Find-SessionFile uses $ProcessId parameter name
    4. All .ps1 files in self_diagnosis/ parse without syntax errors

.NOTES
    Static analysis + PowerShell parser validation. No runtime dependencies.
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

$diagnosePath = Join-Path $RepoRoot "tests\self_diagnosis\diagnose.ps1"
$diagnoseContent = Get-Content $diagnosePath -Raw

# 1. diagnose.ps1 parses without syntax errors
$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($diagnosePath, [ref]$null, [ref]$parseErrors)
Check "diagnose.ps1: parses without syntax errors" `
    ($parseErrors.Count -eq 0) `
    "Parse errors: $($parseErrors | ForEach-Object { $_.Message } | Out-String)"

# 2. No function parameter named $Pid (PowerShell read-only variable)
$hasPidParam = $diagnoseContent -match 'function\s+\S+\s*\(\s*\[.*\]\s*\$Pid\b'
Check "diagnose.ps1: no function parameter named `$Pid" `
    (-not $hasPidParam) `
    "`$Pid is a read-only automatic variable in PowerShell"

# 3. Find-SessionFile uses $ProcessId
Check "diagnose.ps1: Find-SessionFile uses `$ProcessId" `
    ($diagnoseContent -match 'function Find-SessionFile\(\[int\]\$ProcessId\)') `
    "Find-SessionFile should use `$ProcessId, not `$Pid"

# 4. $ProcessId is used in the function body (not $Pid)
Check "diagnose.ps1: uses `$ProcessId in regex" `
    ($diagnoseContent -match '\$\{ProcessId\}') `
    "Function body should reference `${ProcessId}, not `${Pid}"

# 5. All .ps1 files parse without syntax errors (excluding known pre-existing issues)
$testDir = Join-Path $RepoRoot "tests\self_diagnosis"
$ps1Files = Get-ChildItem $testDir -Filter "*.ps1"
# Known exclusions for files with pre-existing parse issues (currently none).
$knownExclusions = @()
$allParsed = $true
$parseFailures = @()
$checkedCount = 0
foreach ($file in $ps1Files) {
    if ($knownExclusions -contains $file.Name) { continue }
    $checkedCount++
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors)
    if ($errors.Count -gt 0) {
        $allParsed = $false
        $parseFailures += "$($file.Name): $($errors[0].Message)"
    }
}
Check "All .ps1 test files parse without errors ($checkedCount checked, $($knownExclusions.Count) excluded)" `
    $allParsed `
    "Failures: $($parseFailures -join '; ')"

# Summary
Write-Host ""
Write-Host "diagnose.ps1 syntax test: $pass PASS / $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
exit $fail
