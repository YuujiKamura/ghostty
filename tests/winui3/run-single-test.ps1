param(
    [string]$TestName = "test-08-keyboard-input",
    [string]$ExePath
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\test-helpers.psm1" -Force -WarningAction SilentlyContinue

# Default exe path relative to repo root
if (-not $ExePath) {
    $ExePath = Join-Path $PSScriptRoot "..\..\zig-out-winui3\bin\ghostty.exe"
}

# Standalone tests (Phase 3) manage their own process — don't launch ghostty for them.
$standaloneTests = @("test-05-ghost-demo")
if ($TestName -in $standaloneTests) {
    Write-Host "Standalone test: $TestName (manages its own ghostty process)"
    $testFile = Join-Path $PSScriptRoot "$TestName.ps1"
    & $testFile
    exit $LASTEXITCODE
}

# Find or launch ghostty
$proc = Get-Process ghostty -ErrorAction SilentlyContinue | Select-Object -First 1
$launched = $false
if (-not $proc) {
    Write-Host "Launching ghostty..."
    $proc = Start-Process -FilePath $ExePath -PassThru
    $launched = $true
    Start-Sleep -Seconds 5
}

$hwnd = Find-GhosttyWindow -ProcessId $proc.Id -TimeoutMs 10000
Write-Host "HWND: 0x$($hwnd.ToString('X'))"
Write-Host "PID: $($proc.Id)"

# Bring window to foreground via Win32 (UIA may timeout on XAML Islands)
[Win32]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 500

# Run the test (pass both Hwnd and ProcessId)
$testFile = Join-Path $PSScriptRoot "$TestName.ps1"
& $testFile -Hwnd $hwnd -ProcessId $proc.Id

# Cleanup
if ($launched) {
    Stop-Ghostty -Process $proc
}
