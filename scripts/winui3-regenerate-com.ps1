param(
    [string]$RepoRoot = "C:\Users\yuuji\ghostty-win",
    [string]$ToolDir = "",
    [string]$WinmdPath = "",
    [string]$ConfigPath = "C:\Users\yuuji\ghostty-win\contracts\winui3-com-generator-input.json",
    [string]$OutPath = "C:\Users\yuuji\ghostty-win\tmp\com.generated.zig",
    [string]$ValidatePath = "",
    [switch]$ValidateOnly,
    [switch]$Deploy
)

$ErrorActionPreference = "Stop"

function Find-Winmd {
    $base = Join-Path $env:USERPROFILE ".nuget\packages\microsoft.windowsappsdk"
    if (-not (Test-Path -LiteralPath $base)) {
        throw "WindowsAppSDK package directory not found: $base"
    }
    $candidates = @(Get-ChildItem -LiteralPath $base -Directory |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName "lib\uap10.0\Microsoft.UI.Xaml.winmd" } |
        Where-Object { Test-Path -LiteralPath $_ })
    if ($candidates.Count -eq 0) {
        throw "Microsoft.UI.Xaml.winmd not found under $base"
    }
    return ($candidates | Select-Object -First 1)
}

function Validate-GeneratedFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Cfg
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Generated file missing: $Path"
    }

    $content = Get-Content -Raw -Path $Path
    foreach ($pat in $Cfg.required_patterns) {
        if ($content -notmatch [regex]::Escape([string]$pat)) {
            throw "Generated output missing required pattern: $pat"
        }
    }
    if ($Cfg.required_regex_patterns) {
        foreach ($rx in $Cfg.required_regex_patterns) {
            if ($content -notmatch [string]$rx) {
                throw "Generated output missing required regex pattern: $rx"
            }
        }
    }
    if ($Cfg.forbidden_patterns) {
        foreach ($pat in $Cfg.forbidden_patterns) {
            if ($content -match [regex]::Escape([string]$pat)) {
                throw "Generated output contains forbidden pattern: $pat"
            }
        }
    }
}

if (-not (Test-Path -LiteralPath $RepoRoot)) { throw "RepoRoot not found: $RepoRoot" }
if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "Config not found: $ConfigPath" }

$cfg = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
if (-not $cfg.interfaces -or $cfg.interfaces.Count -eq 0) {
    throw "Config interfaces is empty: $ConfigPath"
}

if ($ValidatePath) {
    Validate-GeneratedFile -Path $ValidatePath -Cfg $cfg
    Write-Host "Validated: $ValidatePath"
    if ($ValidateOnly) { return }
}

if (-not $ToolDir) {
    $external = Join-Path (Split-Path -Parent $RepoRoot) "win-zig-bindgen"
    $local = Join-Path $RepoRoot "tools\winmd2zig"
    if (Test-Path -LiteralPath $external) {
        $ToolDir = $external
    } elseif (Test-Path -LiteralPath $local) {
        $ToolDir = $local
    } else {
        throw "Generator tool dir not found (checked: $external, $local)"
    }
}
if (-not (Test-Path -LiteralPath $ToolDir)) { throw "ToolDir not found: $ToolDir" }

if (-not $WinmdPath) { $WinmdPath = Find-Winmd }
if (-not (Test-Path -LiteralPath $WinmdPath)) { throw "WinMD not found: $WinmdPath" }

$args = @("--winmd", $WinmdPath, "--deploy", $OutPath)
foreach ($iface in $cfg.interfaces) {
    $args += @("--iface", [string]$iface)
}
if ($cfg.optional_interfaces) {
    foreach ($iface in $cfg.optional_interfaces) {
        $args += @("--iface", [string]$iface)
    }
}

Push-Location $ToolDir
try {
    & zig build run -- @args 2>$null
    if ($LASTEXITCODE -ne 0 -and $cfg.optional_interfaces) {
        # Retry without optional interfaces for single-winmd runs.
        $argsRequired = @("--winmd", $WinmdPath, "--deploy", $OutPath)
        foreach ($iface in $cfg.interfaces) { $argsRequired += @("--iface", [string]$iface) }
        & zig build run -- @argsRequired 2>$null
    }
    if ($LASTEXITCODE -ne 0) {
        throw "win-zig-bindgen failed (exit=$LASTEXITCODE). Check interface names and WinMD source."
    }
}
finally {
    Pop-Location
}

Validate-GeneratedFile -Path $OutPath -Cfg $cfg

Write-Host "Generated and validated: $OutPath"

if ($Deploy) {
    $dest = Join-Path $RepoRoot "src\apprt\winui3\com.zig"
    Copy-Item -LiteralPath $OutPath -Destination $dest -Force
    Validate-GeneratedFile -Path $dest -Cfg $cfg
    Write-Host "Deployed: $dest"
}
