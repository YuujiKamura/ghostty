param(
    [string]$RepoRoot = "",
    [string]$ToolDir = "",
    [string]$ComPath = "",
    [string]$WinmdPath = "",
    [switch]$Check
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
if (-not $ComPath) {
    $ComPath = Join-Path $RepoRoot "src\apprt\winui3\com.zig"
}
if (-not (Test-Path -LiteralPath $ComPath)) {
    throw "com.zig not found: $ComPath"
}
if (-not (Test-Path -LiteralPath $ToolDir)) {
    throw "winmd2zig tool dir not found: $ToolDir"
}

$generated = $null
Push-Location $ToolDir
try {
    $generated = & zig build run -- --emit-tabview-delegate-zig $WinmdPath 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to generate delegate IID constants from winmd2zig"
    }
}
finally {
    Pop-Location
}

$text = Get-Content -Raw -LiteralPath $ComPath

$map = @{
    "IID_TypedEventHandler_AddTabButtonClick" = ($generated | Select-String "IID_TypedEventHandler_AddTabButtonClick").Line
    "IID_SelectionChangedEventHandler" = ($generated | Select-String "IID_SelectionChangedEventHandler").Line
    "IID_TypedEventHandler_TabCloseRequested" = ($generated | Select-String "IID_TypedEventHandler_TabCloseRequested").Line
}

foreach ($k in $map.Keys) {
    if (-not $map[$k]) {
        throw "Generated output missing constant: $k"
    }
}

function Replace-Const([string]$src, [string]$constName, [string]$newLine) {
    $pattern = "pub const $constName = GUID\{[\s\S]*?\};"
    return [regex]::Replace($src, $pattern, $newLine, [System.Text.RegularExpressions.RegexOptions]::Singleline)
}

$updated = $text
$updated = Replace-Const $updated "IID_TypedEventHandler_AddTabButtonClick" $map["IID_TypedEventHandler_AddTabButtonClick"]
$updated = Replace-Const $updated "IID_SelectionChangedEventHandler" $map["IID_SelectionChangedEventHandler"]
$updated = Replace-Const $updated "IID_TypedEventHandler_TabCloseRequested" $map["IID_TypedEventHandler_TabCloseRequested"]

if ($Check) {
    if ($updated -ne $text) {
        Write-Host "winui3-sync-delegate-iids: OUT-OF-DATE"
        exit 2
    }
    Write-Host "winui3-sync-delegate-iids: OK"
    exit 0
}

if ($updated -ne $text) {
    Set-Content -LiteralPath $ComPath -Value $updated -Encoding UTF8
    Write-Host "Updated: $ComPath"
} else {
    Write-Host "No changes: $ComPath"
}
