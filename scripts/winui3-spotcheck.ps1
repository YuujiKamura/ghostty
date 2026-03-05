param(
    [Parameter(Mandatory = $true)][string]$Path
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Path)) {
    throw "SpotCheck target not found: $Path"
}

$content = Get-Content -Raw -Path $Path

function Require-Regex {
    param([Parameter(Mandatory = $true)][string]$Pattern)
    if ($content -notmatch $Pattern) {
        throw "SpotCheck failed: missing pattern: $Pattern"
    }
}

function Require-Count {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][int]$Expected
    )
    $matches = [regex]::Matches($content, $Pattern)
    if ($matches.Count -ne $Expected) {
        throw "SpotCheck failed: pattern count mismatch ($Pattern) expected=$Expected actual=$($matches.Count)"
    }
}

Require-Count -Pattern "pub const IVector = extern struct \{" -Expected 1
Require-Regex -Pattern "pub fn getTabItems\(self: \*@This\(\)\) !\*IVector"
Require-Regex -Pattern "pub fn addTabCloseRequested\(self: \*@This\(\), p0: anytype\) !EventRegistrationToken"
Require-Regex -Pattern "pub fn addAddTabButtonClick\(self: \*@This\(\), p0: anytype\) !EventRegistrationToken"
Require-Regex -Pattern "pub fn addSelectionChanged\(self: \*@This\(\), p0: anytype\) !EventRegistrationToken"
Require-Regex -Pattern "GetXmlnsDefinitions: \*const fn \(\*anyopaque, \*u32, \*\?\*anyopaque\) callconv\(\.winapi\) HRESULT"

Write-Host "SpotCheck OK: $Path"
