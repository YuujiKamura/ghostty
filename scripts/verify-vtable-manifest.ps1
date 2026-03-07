<#
.SYNOPSIS
    Verifies com_generated.zig against a vtable manifest JSON.
.DESCRIPTION
    Parses COM interface definitions from the generated Zig file and compares
    them field-by-field against the manifest produced by bootstrap-vtable-manifest.ps1.
    Exits 0 on success, 1 on any mismatch.
.PARAMETER ComGenPath
    Path to com_generated.zig.
.PARAMETER ManifestPath
    Path to the vtable manifest JSON.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ComGenPath,

    [Parameter(Mandatory)]
    [string]$ManifestPath
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
$ComGenPath   = (Resolve-Path $ComGenPath).Path
$ManifestPath = (Resolve-Path $ManifestPath).Path

# ---------------------------------------------------------------------------
# GUID conversion (same logic as bootstrap)
# ---------------------------------------------------------------------------
function Convert-ZigGuidToString {
    param([string]$line)
    if ($line -match 'GUID\{\s*\.Data1\s*=\s*0x([0-9a-fA-F]+)\s*,\s*\.Data2\s*=\s*0x([0-9a-fA-F]+)\s*,\s*\.Data3\s*=\s*0x([0-9a-fA-F]+)\s*,\s*\.Data4\s*=\s*\.\{\s*0x([0-9a-fA-F]+)\s*,\s*0x([0-9a-fA-F]+)\s*,\s*0x([0-9a-fA-F]+)\s*,\s*0x([0-9a-fA-F]+)\s*,\s*0x([0-9a-fA-F]+)\s*,\s*0x([0-9a-fA-F]+)\s*,\s*0x([0-9a-fA-F]+)\s*,\s*0x([0-9a-fA-F]+)\s*\}') {
        $d1 = $Matches[1].PadLeft(8, '0').ToLower()
        $d2 = $Matches[2].PadLeft(4, '0').ToLower()
        $d3 = $Matches[3].PadLeft(4, '0').ToLower()
        $d4a = $Matches[4].PadLeft(2, '0').ToLower()
        $d4b = $Matches[5].PadLeft(2, '0').ToLower()
        $d4c = $Matches[6].PadLeft(2, '0').ToLower()
        $d4d = $Matches[7].PadLeft(2, '0').ToLower()
        $d4e = $Matches[8].PadLeft(2, '0').ToLower()
        $d4f = $Matches[9].PadLeft(2, '0').ToLower()
        $d4g = $Matches[10].PadLeft(2, '0').ToLower()
        $d4h = $Matches[11].PadLeft(2, '0').ToLower()
        return "$d1-$d2-$d3-$d4a$d4b-$d4c$d4d$d4e$d4f$d4g$d4h"
    }
    return $null
}

# ---------------------------------------------------------------------------
# Parse com_generated.zig (same state machine as bootstrap)
# ---------------------------------------------------------------------------
$lines = [System.IO.File]::ReadAllLines($ComGenPath)

$parsedInterfaces = [ordered]@{}

$state = 'outside'
$currentName = $null
$currentIID  = $null
$vtableFields = $null

for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]

    switch ($state) {
        'outside' {
            if ($line -match '^\s*pub\s+const\s+(I\w+)\s*=\s*extern\s+struct\s*\{') {
                $currentName = $Matches[1]
                $currentIID  = $null
                $vtableFields = $null
                $state = 'in_struct'
            }
        }
        'in_struct' {
            if ($line -match '^\s*pub\s+const\s+IID\s*=') {
                $currentIID = Convert-ZigGuidToString $line
            }
            elseif ($line -match '^\s*pub\s+const\s+VTable\s*=\s*extern\s+struct\s*\{') {
                $vtableFields = [System.Collections.Generic.List[string]]::new()
                $state = 'in_vtable'
            }
            elseif ($line -match '^\};') {
                if ($currentName -and $currentIID -and $vtableFields) {
                    $parsedInterfaces[$currentName] = @{
                        iid    = $currentIID
                        fields = $vtableFields.ToArray()
                    }
                }
                $state = 'outside'
            }
        }
        'in_vtable' {
            if ($line -match '^\s{8}(\w+)\s*:') {
                $vtableFields.Add($Matches[1])
            }
            elseif ($line -match '^\s{4}\};') {
                $state = 'in_struct'
            }
        }
    }
}

# Derive methods from fields (same logic as bootstrap)
function Get-Methods {
    param([string]$name, [string[]]$fields)
    if ($name -eq 'IUnknown') {
        return $fields
    }
    elseif ($name -eq 'IInspectable') {
        return @($fields | Select-Object -Skip 3)
    }
    else {
        return @($fields | Select-Object -Skip 6)
    }
}

# ---------------------------------------------------------------------------
# Load manifest
# ---------------------------------------------------------------------------
$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------
$errors = [System.Collections.Generic.List[string]]::new()
$verified = 0

foreach ($prop in $manifest.interfaces.PSObject.Properties) {
    $name = $prop.Name
    $mEntry = $prop.Value

    if (-not $parsedInterfaces.Contains($name)) {
        $errors.Add("VTABLE MISSING: $name exists in manifest but not in com_generated.zig")
        continue
    }

    $pEntry = $parsedInterfaces[$name]
    $pMethods = @(Get-Methods -name $name -fields $pEntry.fields)
    $pTotalSlots = $pEntry.fields.Count

    $mismatch = $false
    $details = [System.Collections.Generic.List[string]]::new()

    # Compare IID
    if ($mEntry.iid -ne $pEntry.iid) {
        $details.Add("  IID: manifest=`"$($mEntry.iid)`", generated=`"$($pEntry.iid)`"")
        $mismatch = $true
    }

    # Compare total slots
    if ($mEntry.total_slots -ne $pTotalSlots) {
        $details.Add("  Total slots: manifest=$($mEntry.total_slots), generated=$pTotalSlots")
        $mismatch = $true
    }

    # Compare methods
    $mMethods = @($mEntry.methods)
    $methodCountMismatch = $mMethods.Count -ne $pMethods.Count

    if ($methodCountMismatch) {
        $details.Add("  Methods count: manifest=$($mMethods.Count), generated=$($pMethods.Count)")
        $mismatch = $true
    }

    # Compare individual method slots
    $maxSlots = [Math]::Max($mMethods.Count, $pMethods.Count)
    # Determine base offset for slot numbering
    if ($name -eq 'IUnknown') { $baseOffset = 0 }
    elseif ($name -eq 'IInspectable') { $baseOffset = 3 }
    else { $baseOffset = 6 }

    for ($j = 0; $j -lt $maxSlots; $j++) {
        $slotNum = $baseOffset + $j
        $mMethod = if ($j -lt $mMethods.Count) { $mMethods[$j] } else { "(absent)" }
        $pMethod = if ($j -lt $pMethods.Count) { $pMethods[$j] } else { "(absent)" }
        if ($mMethod -ne $pMethod) {
            $details.Add("  Slot ${slotNum}: manifest=`"$mMethod`", generated=`"$pMethod`"")
            $mismatch = $true
        }
    }

    if ($mismatch) {
        $errors.Add("VTABLE MISMATCH: $name")
        foreach ($d in $details) {
            $errors.Add($d)
        }
    }
    else {
        $verified++
    }
}

# Check for interfaces in .zig not in manifest (warnings only)
$warnings = 0
foreach ($name in $parsedInterfaces.Keys) {
    $found = $false
    foreach ($prop in $manifest.interfaces.PSObject.Properties) {
        if ($prop.Name -eq $name) { $found = $true; break }
    }
    if (-not $found) {
        Write-Warning "Interface $name found in com_generated.zig but not in manifest (new interface?)"
        $warnings++
    }
}

# ---------------------------------------------------------------------------
# Output results
# ---------------------------------------------------------------------------
if ($errors.Count -gt 0) {
    foreach ($err in $errors) {
        Write-Host $err -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "VTABLE MANIFEST FAILED: $($errors.Count) error(s), $verified interface(s) OK" -ForegroundColor Red
    exit 1
}
else {
    $msg = "VTABLE MANIFEST OK: $verified interfaces verified"
    if ($warnings -gt 0) {
        $msg += " ($warnings new interface(s) not in manifest)"
    }
    Write-Host $msg -ForegroundColor Green
    exit 0
}
