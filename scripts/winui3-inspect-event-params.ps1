param(
    [string]$RepoRoot = "",
    [string]$ToolDir = "",
    [string]$WinmdPath = ""
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

function Find-Winmd {
    $base = Join-Path $env:USERPROFILE ".nuget\packages\microsoft.windowsappsdk"
    if (-not (Test-Path -LiteralPath $base)) {
        throw "WindowsAppSDK package directory not found: $base"
    }
    $candidates = @(Get-ChildItem -LiteralPath $base -Directory |
        Sort-Object Name -Descending |
        ForEach-Object {
            Join-Path $_.FullName "lib\uap10.0\Microsoft.UI.Xaml.winmd"
        } |
        Where-Object { Test-Path -LiteralPath $_ })
    if (-not $candidates -or $candidates.Count -eq 0) {
        throw "Microsoft.UI.Xaml.winmd not found under $base"
    }
    return ($candidates | Select-Object -First 1)
}

if (-not $WinmdPath) {
    $WinmdPath = Find-Winmd
}
if (-not (Test-Path -LiteralPath $WinmdPath)) {
    throw "WinMD not found: $WinmdPath"
}

if (-not $ToolDir) {
    $externalToolDir = Join-Path (Split-Path -Parent $RepoRoot) "win-zig-bindgen"
    $localToolDir = Join-Path $RepoRoot "tools\winmd2zig"
    $ToolDir = if (Test-Path -LiteralPath $externalToolDir) { $externalToolDir } else { $localToolDir }
}
if (-not (Test-Path -LiteralPath $ToolDir)) {
    throw "winmd2zig tool dir not found: $ToolDir"
}

Push-Location $ToolDir
try {
    zig build | Out-Null

    $events = @(
        "add_TabCloseRequested",
        "add_AddTabButtonClick",
        "add_SelectionChanged"
    )

    foreach ($e in $events) {
        Write-Host ("=== inspect {0} ===" -f $e)
        & .\zig-out\bin\winmd2zig.exe --inspect-event-param $WinmdPath "Microsoft.UI.Xaml.Controls.ITabView" $e
        if ($LASTEXITCODE -ne 0) {
            throw "inspect-event-param failed for: $e"
        }
        Write-Host ""
    }
}
finally {
    Pop-Location
}
