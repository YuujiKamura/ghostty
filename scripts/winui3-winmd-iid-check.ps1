param(
    [string]$RepoRoot = ".",
    [string]$ToolDir = ""
)

$ErrorActionPreference = "Stop"

function Resolve-WinmdPath {
    $base = Join-Path $env:USERPROFILE ".nuget\packages\microsoft.windowsappsdk"
    if (-not (Test-Path $base)) { throw "WindowsAppSDK NuGet cache not found: $base" }
    $cand = @(Get-ChildItem $base -Directory | ForEach-Object {
        Join-Path $_.FullName "lib\uap10.0\Microsoft.UI.Xaml.winmd"
    } | Where-Object { Test-Path $_ } | Sort-Object -Descending)
    if ($cand.Count -eq 0) { throw "Microsoft.UI.Xaml.winmd not found under $base" }
    return ($cand | Select-Object -First 1)
}

function Resolve-ToolDir([string]$repoRoot, [string]$toolDirArg) {
    if ($toolDirArg -and (Test-Path $toolDirArg)) { return $toolDirArg }
    $external = Join-Path (Split-Path -Parent $repoRoot) "win-zig-bindgen"
    if (Test-Path $external) { return $external }
    throw "win-zig-bindgen tool dir not found. Set -ToolDir explicitly."
}

function GuidLiteralFromText([string]$text) {
    $flat = ($text -replace "`r", " " -replace "`n", " ")
    $m = [regex]::Match($flat, "GUID\{[^}]*\}")
    if (-not $m.Success) { return $null }
    return $m.Value.Trim()
}

function Normalize-GuidLiteral([string]$s) {
    if (-not $s) { return $s }
    return ($s -replace "\s+", "").ToLowerInvariant()
}

function Get-GuidForSymbol($lines, [string]$symbol) {
    $structIdx = ($lines | Select-String -SimpleMatch "pub const $symbol = extern struct {" | Select-Object -First 1).LineNumber
    if ($structIdx) {
        $chunk = (($lines | Select-Object -Skip $structIdx -First 12) -join "`n")
        return (GuidLiteralFromText $chunk)
    }

    $constIdx = ($lines | Select-String -SimpleMatch "pub const $symbol = GUID{" | Select-Object -First 1).LineNumber
    if ($constIdx) {
        $chunk = (($lines | Select-Object -Skip ($constIdx - 1) -First 4) -join "`n")
        return (GuidLiteralFromText $chunk)
    }

    return $null
}

$repoRoot = (Resolve-Path $RepoRoot).Path
$toolDir = Resolve-ToolDir -repoRoot $repoRoot -toolDirArg $ToolDir
$comPath = Join-Path $repoRoot "src\apprt\winui3\com.zig"
if (-not (Test-Path $comPath)) { throw "com.zig not found: $comPath" }

$winmd = Resolve-WinmdPath

Push-Location $toolDir
try {
    $tmp = Join-Path $env:TEMP ("probe_com_{0}.zig" -f ([guid]::NewGuid().ToString("N")))
    & .\zig-out\bin\win-zig-bindgen.exe -o $tmp $winmd `
        Microsoft.UI.Xaml.Controls.IControl `
        Microsoft.UI.Xaml.Media.ISolidColorBrush `
        Microsoft.UI.Xaml.Controls.ITabViewTabCloseRequestedEventArgs `
        Microsoft.UI.Xaml.IFrameworkElement `
        Microsoft.UI.Xaml.RoutedEventHandler
    if ($LASTEXITCODE -ne 0) {
        throw "win-zig-bindgen generation failed (exit=$LASTEXITCODE)"
    }
} finally {
    Pop-Location
}

$generated = Get-Content $tmp
$current = Get-Content $comPath

$targets = @(
    @{ Name = "IControl"; Gen = "IControl"; Cur = "IControl" },
    @{ Name = "ISolidColorBrush"; Gen = "ISolidColorBrush"; Cur = "ISolidColorBrush" },
    @{ Name = "ITabViewTabCloseRequestedEventArgs"; Gen = "ITabViewTabCloseRequestedEventArgs"; Cur = "ITabViewTabCloseRequestedEventArgs" },
    @{ Name = "IFrameworkElement"; Gen = "IFrameworkElement"; Cur = "IFrameworkElement" },
    @{ Name = "RoutedEventHandler"; Gen = "RoutedEventHandler"; Cur = "IID_RoutedEventHandler" }
)

$errors = @()
foreach ($target in $targets) {
    $name = $target.Name
    $genGuid = Get-GuidForSymbol $generated $target.Gen
    $curGuid = Get-GuidForSymbol $current $target.Cur
    if (-not $genGuid -or -not $curGuid) {
        $errors += "${name}: IID parse failed (gen=$($target.Gen) cur=$($target.Cur))"
        continue
    }

    if ($curGuid -match "Data1 = 0x00000000") {
        $errors += "${name}: current IID is ZERO placeholder"
        continue
    }

    if ((Normalize-GuidLiteral $genGuid) -ne (Normalize-GuidLiteral $curGuid)) {
        $errors += "${name}: IID mismatch`n  generated: $genGuid`n  current:   $curGuid"
    }
}

Remove-Item $tmp -Force -ErrorAction SilentlyContinue

if ($errors.Count -gt 0) {
    Write-Host "winui3-winmd-iid-check: FAIL"
    $errors | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "winui3-winmd-iid-check: PASS"
exit 0
