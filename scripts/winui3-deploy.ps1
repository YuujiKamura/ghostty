param(
    [string]$RepoRoot = "C:\Users\yuuji\ghostty-win",
    [switch]$SkipRuntimeTest,
    [switch]$SkipGhosttyBuild
)

$ErrorActionPreference = "Stop"

function Ensure-WindowsAppRuntimeBootstrapDll {
    param(
        [Parameter(Mandatory = $true)][string]$GhosttyBinDir,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    $dllName = "Microsoft.WindowsAppRuntime.Bootstrap.dll"
    $dst = Join-Path $GhosttyBinDir $dllName
    if (Test-Path -LiteralPath $dst) {
        Write-Host "Bootstrap already present: $dst"
        return
    }

    $candidates = @(
        (Join-Path $RepoRoot "third_party\windowsappruntime\$dllName"),
        (Join-Path $RepoRoot "deps\windowsappruntime\$dllName"),
        (Join-Path $RepoRoot $dllName),
        (Join-Path $env:ProgramFiles "Microsoft\WindowsAppRuntime\$dllName"),
        (Join-Path $env:ProgramFiles "WindowsApps\$dllName")
    )

    if ($env:ProgramFiles -and ${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} "Microsoft\WindowsAppRuntime\$dllName")
    }
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\$dllName")
    }

    $searchRoots = @(
        (Join-Path $env:ProgramFiles "WindowsApps"),
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)}
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    foreach ($root in $searchRoots) {
        try {
            $hit = Get-ChildItem -Path $root -Filter $dllName -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($hit) { $candidates += $hit.FullName }
        } catch {}
    }

    $src = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (-not $src) {
        throw "Missing $dllName. Looked in: $($candidates -join '; ')"
    }

    New-Item -ItemType Directory -Path $GhosttyBinDir -Force | Out-Null
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host "Copied $dllName -> $dst (from $src)"
}

if (-not (Test-Path -LiteralPath $RepoRoot)) {
    throw "RepoRoot not found: $RepoRoot"
}

$scriptRoot = Join-Path $RepoRoot "scripts"
$regenScript = Join-Path $scriptRoot "winui3-regenerate-com.ps1"
$spotScript = Join-Path $scriptRoot "winui3-spotcheck.ps1"
$tmpGenerated = Join-Path $RepoRoot "tmp\com.generated.zig"
$deployTarget = Join-Path $RepoRoot "src\apprt\winui3\com.zig"

if (-not (Test-Path -LiteralPath $regenScript)) { throw "Missing script: $regenScript" }
if (-not (Test-Path -LiteralPath $spotScript)) { throw "Missing script: $spotScript" }

Write-Host "[1/6] Regenerate + contract gate (tmp)"
& $regenScript -RepoRoot $RepoRoot

Write-Host "[2/6] SpotCheck tmp output"
& $spotScript -Path $tmpGenerated

Write-Host "[3/6] Deploy com.zig + contract gate"
& $regenScript -RepoRoot $RepoRoot -Deploy

Write-Host "[4/6] Validate deployed com.zig"
& $regenScript -RepoRoot $RepoRoot -ValidatePath $deployTarget -ValidateOnly
& $spotScript -Path $deployTarget

Push-Location $RepoRoot
try {
    if (-not $SkipRuntimeTest) {
        Write-Host "[5/6] zig test src/apprt/winui3/com_runtime.zig"
        & zig test src/apprt/winui3/com_runtime.zig
        if ($LASTEXITCODE -ne 0) { throw "com_runtime test failed (exit=$LASTEXITCODE)" }
    } else {
        Write-Host "[5/6] Skipped com_runtime test"
    }

    if (-not $SkipGhosttyBuild) {
        Write-Host "[6/6] zig build -Dtarget=x86_64-windows -Dapp-runtime=winui3 -Drenderer=d3d11"
        & zig build -Dtarget=x86_64-windows -Dapp-runtime=winui3 -Drenderer=d3d11
        if ($LASTEXITCODE -ne 0) { throw "ghostty build failed (exit=$LASTEXITCODE)" }
        $ghosttyBin = Join-Path $RepoRoot "zig-out\bin"
        Ensure-WindowsAppRuntimeBootstrapDll -GhosttyBinDir $ghosttyBin -RepoRoot $RepoRoot
    } else {
        Write-Host "[6/6] Skipped ghostty build"
    }
}
finally {
    Pop-Location
}

Write-Host "Deploy + checks passed"
