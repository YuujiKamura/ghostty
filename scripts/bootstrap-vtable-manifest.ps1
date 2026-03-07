<#
.SYNOPSIS
    Bootstraps a vtable manifest JSON from com_generated.zig.
.DESCRIPTION
    Parses COM interface definitions from the generated Zig file and produces
    a JSON manifest capturing interface names, IIDs, base interfaces, method
    names, and total vtable slot counts. Used as the ground-truth for
    verify-vtable-manifest.ps1.
.PARAMETER ComGenPath
    Path to com_generated.zig. Defaults to the repo's standard location.
.PARAMETER OutPath
    Path to write the manifest JSON. Defaults to contracts/vtable_manifest.json.
#>
[CmdletBinding()]
param(
    [string]$ComGenPath,
    [string]$OutPath
)

$ErrorActionPreference = "Stop"

# Resolve script directory reliably (works with -File invocation too)
$_scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent (Resolve-Path $MyInvocation.MyCommand.Path) }

if (-not $ComGenPath) {
    $ComGenPath = Join-Path $_scriptDir '..\src\apprt\winui3\com_generated.zig'
}
if (-not $OutPath) {
    $OutPath = Join-Path $_scriptDir '..\contracts\vtable_manifest.json'
}

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
$ComGenPath = (Resolve-Path $ComGenPath).Path
$outDir = Split-Path $OutPath -Parent
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

# ---------------------------------------------------------------------------
# Read source
# ---------------------------------------------------------------------------
$lines = [System.IO.File]::ReadAllLines($ComGenPath)

# ---------------------------------------------------------------------------
# State-machine parser
# ---------------------------------------------------------------------------
$interfaces = [ordered]@{}

# States: outside, in_struct, in_vtable
$state = 'outside'
$currentName = $null
$currentIID  = $null
$vtableFields = $null

function Convert-ZigGuidToString {
    param([string]$line)
    # Extract Data1, Data2, Data3, Data4 bytes from the GUID literal
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

for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]

    switch ($state) {
        'outside' {
            # Match: pub const IFoo = extern struct {
            if ($line -match '^\s*pub\s+const\s+(I\w+)\s*=\s*extern\s+struct\s*\{') {
                $currentName = $Matches[1]
                $currentIID  = $null
                $vtableFields = $null
                $state = 'in_struct'
            }
        }
        'in_struct' {
            # Match IID line
            if ($line -match '^\s*pub\s+const\s+IID\s*=') {
                $currentIID = Convert-ZigGuidToString $line
            }
            # Match VTable start
            elseif ($line -match '^\s*pub\s+const\s+VTable\s*=\s*extern\s+struct\s*\{') {
                $vtableFields = [System.Collections.Generic.List[string]]::new()
                $state = 'in_vtable'
            }
            # Match struct closing (interface ends without us finding VTable — skip)
            elseif ($line -match '^\};') {
                # End of interface struct — emit if we have data
                if ($currentName -and $currentIID -and $vtableFields) {
                    $interfaces[$currentName] = @{
                        iid    = $currentIID
                        fields = $vtableFields.ToArray()
                    }
                }
                $state = 'outside'
            }
        }
        'in_vtable' {
            # Match VTable field: "        FieldName: ..." (8 spaces indent, identifier, colon)
            if ($line -match '^\s{8}(\w+)\s*:') {
                $vtableFields.Add($Matches[1])
            }
            # Match VTable closing: "    };" (4 spaces indent)
            elseif ($line -match '^\s{4}\};') {
                $state = 'in_struct'
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Build output structure
# ---------------------------------------------------------------------------
$output = [ordered]@{
    version    = 1
    source     = "bootstrapped from com_generated.zig"
    interfaces = [ordered]@{}
}

foreach ($name in $interfaces.Keys) {
    $entry = $interfaces[$name]
    $fields = $entry.fields

    if ($name -eq 'IUnknown') {
        $base = $null
        $methods = $fields
        $totalSlots = $fields.Count
    }
    elseif ($name -eq 'IInspectable') {
        $base = 'IUnknown'
        # First 3 are IUnknown base slots
        $methods = @($fields | Select-Object -Skip 3)
        $totalSlots = $fields.Count
    }
    else {
        $base = 'IInspectable'
        # First 6 are IInspectable base slots
        $methods = @($fields | Select-Object -Skip 6)
        $totalSlots = $fields.Count
    }

    $output.interfaces[$name] = [ordered]@{
        iid         = $entry.iid
        base        = $base
        methods     = @($methods)
        total_slots = $totalSlots
    }
}

# ---------------------------------------------------------------------------
# Write JSON
# ---------------------------------------------------------------------------
$json = $output | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($OutPath, $json, [System.Text.Encoding]::UTF8)

$count = $output.interfaces.Count
Write-Host "VTABLE MANIFEST BOOTSTRAPPED: $count interfaces written to $OutPath"
