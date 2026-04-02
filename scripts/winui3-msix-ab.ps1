param(
    [switch]$NoBuild,
    [int]$ObserveSec = 35,
    [string]$PackageName = "YuujiKamura.GhosttyProbe",
    [string]$Publisher = "CN=GhosttyProbe",
    [string]$Version = "1.0.0.0"
)

$ErrorActionPreference = "Stop"

function Out-Info([string]$m) { Write-Host "[INFO] $m" }
function Out-Ok([string]$m) { Write-Host "[ OK ] $m" -ForegroundColor Green }
function Out-Warn([string]$m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }

function Resolve-SdkTool([string]$toolName) {
    $root = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
    if (-not (Test-Path $root)) { throw "Windows Kits not found: $root" }
    $hits = Get-ChildItem -Path $root -Recurse -File -Filter $toolName -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "\\x64\\" } |
        Sort-Object FullName -Descending
    if (-not $hits) { throw "$toolName not found under $root" }
    return $hits[0].FullName
}

function Write-TinyPng([string]$path) {
    $base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO2Jx7kAAAAASUVORK5CYII="
    [IO.File]::WriteAllBytes($path, [Convert]::FromBase64String($base64))
}

function Wait-NewGhosttyProcess([datetime]$after, [int]$timeoutSec) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        $p = Get-Process -Name ghostty -ErrorAction SilentlyContinue |
            Where-Object { $_.StartTime -gt $after } |
            Sort-Object StartTime -Descending |
            Select-Object -First 1
        if ($p) { return $p }
        Start-Sleep -Milliseconds 300
    }
    return $null
}

function Run-Unpackaged([string]$exePath, [int]$observeSec) {
    Out-Info "A(unpackaged): start $exePath"
    $p = Start-Process -FilePath $exePath -PassThru
    Start-Sleep -Seconds $observeSec
    $alive = -not $p.HasExited
    $exitCode = $null
    if (-not $alive) { $exitCode = $p.ExitCode }
    if ($alive) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
    return @{
        Mode = "unpackaged"
        Alive = $alive
        ExitCode = $exitCode
        Pid = $p.Id
    }
}

function Run-Packaged([string]$aumid, [int]$observeSec) {
    Out-Info "B(packaged): start shell:AppsFolder\\$aumid"
    $t0 = Get-Date
    Start-Process -FilePath "explorer.exe" -ArgumentList "shell:AppsFolder\$aumid" | Out-Null
    $p = Wait-NewGhosttyProcess -after $t0 -timeoutSec 20
    if (-not $p) {
        return @{
            Mode = "packaged"
            Alive = $false
            ExitCode = "NO_PROCESS"
            Pid = $null
        }
    }
    Start-Sleep -Seconds $observeSec
    try { $p.Refresh() } catch {}
    $alive = -not $p.HasExited
    $exitCode = $null
    if (-not $alive) { $exitCode = $p.ExitCode }
    if ($alive) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
    return @{
        Mode = "packaged"
        Alive = $alive
        ExitCode = $exitCode
        Pid = $p.Id
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot
$tmpRoot = Join-Path $repoRoot "tmp\msix-ab"
$stageDir = Join-Path $tmpRoot "layout"
$assetDir = Join-Path $stageDir "Assets"
$vfsDir = Join-Path $stageDir "VFS\ProgramFilesX64\ghostty"
$msixPath = Join-Path $tmpRoot "GhosttyProbe.msix"
$pfxPath = Join-Path $tmpRoot "GhosttyProbe.pfx"
$cerPath = Join-Path $tmpRoot "GhosttyProbe.cer"
$pfxPassword = "ghostty-probe-123!"

New-Item -ItemType Directory -Force -Path $tmpRoot,$assetDir,$vfsDir | Out-Null

if (-not $NoBuild) {
    Out-Info "Build winui3 binary"
    & zig build -Dtarget=x86_64-windows -Dapp-runtime=winui3 -Drenderer=d3d11
}

$exe = Join-Path $repoRoot "zig-out\bin\ghostty.exe"
if (-not (Test-Path $exe)) { throw "Missing executable: $exe" }

Copy-Item -Force $exe (Join-Path $vfsDir "ghostty.exe")
$bootstrapDll = Join-Path $repoRoot "zig-out\bin\Microsoft.WindowsAppRuntime.Bootstrap.dll"
if (Test-Path $bootstrapDll) {
    Copy-Item -Force $bootstrapDll (Join-Path $vfsDir "Microsoft.WindowsAppRuntime.Bootstrap.dll")
}

Write-TinyPng (Join-Path $assetDir "StoreLogo.png")
Copy-Item -Force (Join-Path $assetDir "StoreLogo.png") (Join-Path $assetDir "Square44x44Logo.png")
Copy-Item -Force (Join-Path $assetDir "StoreLogo.png") (Join-Path $assetDir "Square150x150Logo.png")

$manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package
  xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
  xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
  xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
  IgnorableNamespaces="uap rescap">
  <Identity Name="$PackageName" Publisher="$Publisher" Version="$Version" />
  <Properties>
    <DisplayName>Ghostty Probe</DisplayName>
    <PublisherDisplayName>Ghostty Probe</PublisherDisplayName>
    <Logo>Assets\StoreLogo.png</Logo>
  </Properties>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.26100.0" />
  </Dependencies>
  <Resources>
    <Resource Language="en-us" />
  </Resources>
  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
  <Applications>
    <Application Id="App" Executable="VFS\ProgramFilesX64\ghostty\ghostty.exe" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements
        DisplayName="Ghostty Probe"
        Description="Ghostty Probe"
        BackgroundColor="transparent"
        Square150x150Logo="Assets\Square150x150Logo.png"
        Square44x44Logo="Assets\Square44x44Logo.png" />
    </Application>
  </Applications>
</Package>
"@
Set-Content -Path (Join-Path $stageDir "AppxManifest.xml") -Value $manifest -Encoding UTF8

$makeappx = Resolve-SdkTool -toolName "makeappx.exe"
$signtool = Resolve-SdkTool -toolName "signtool.exe"
Out-Info "Using makeappx: $makeappx"
Out-Info "Using signtool: $signtool"

$existing = Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue
if ($existing) {
    Out-Warn "Removing existing package $PackageName"
    $existing | Remove-AppxPackage -ErrorAction SilentlyContinue
}

$cert = $null
Out-Info "Creating code-signing certificate $Publisher"
$cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $Publisher -KeyAlgorithm RSA -KeyLength 2048 -KeyExportPolicy Exportable -CertStoreLocation "Cert:\CurrentUser\My" -NotAfter (Get-Date).AddYears(3)
Export-Certificate -Cert $cert -FilePath $cerPath | Out-Null
Import-Certificate -FilePath $cerPath -CertStoreLocation "Cert:\CurrentUser\TrustedPeople" | Out-Null
Import-Certificate -FilePath $cerPath -CertStoreLocation "Cert:\CurrentUser\Root" | Out-Null
$sec = ConvertTo-SecureString -String $pfxPassword -Force -AsPlainText
Export-PfxCertificate -Cert "Cert:\CurrentUser\My\$($cert.Thumbprint)" -FilePath $pfxPath -Password $sec | Out-Null

if (Test-Path $msixPath) { Remove-Item -Force $msixPath }
& $makeappx pack /d $stageDir /p $msixPath /o
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $msixPath)) {
    throw "makeappx failed (exit=$LASTEXITCODE)"
}
& $signtool sign /fd SHA256 /f $pfxPath /p $pfxPassword $msixPath
if ($LASTEXITCODE -ne 0) {
    throw "signtool failed (exit=$LASTEXITCODE)"
}
Add-AppxPackage -Path $msixPath
Out-Ok "Installed $msixPath"

$pkg = Get-AppxPackage -Name $PackageName -ErrorAction Stop | Select-Object -First 1
$aumid = "$($pkg.PackageFamilyName)!App"

$a = Run-Unpackaged -exePath $exe -observeSec $ObserveSec
$b = Run-Packaged -aumid $aumid -observeSec $ObserveSec

Write-Host ""
Write-Host "=== MSIX A/B Result ==="
Write-Host ("A {0}: alive={1} exit={2} pid={3}" -f $a.Mode, $a.Alive, $a.ExitCode, $a.Pid)
Write-Host ("B {0}: alive={1} exit={2} pid={3}" -f $b.Mode, $b.Alive, $b.ExitCode, $b.Pid)
Write-Host ("AUMID: {0}" -f $aumid)
Write-Host ("MSIX : {0}" -f $msixPath)
