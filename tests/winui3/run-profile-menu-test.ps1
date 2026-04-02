$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\test-helpers.psm1" -Force -WarningAction SilentlyContinue

$ExePath = Join-Path $PSScriptRoot "..\..\zig-out-winui3\bin\ghostty.exe"

# Launch ghostty
Write-Host "Launching ghostty..."
$proc = Start-Process -FilePath $ExePath -PassThru
Write-Host "PID: $($proc.Id)"
Start-Sleep -Seconds 10

# Find window with longer timeout
$hwnd = Find-GhosttyWindow -ProcessId $proc.Id -TimeoutMs 20000
Write-Host "HWND: 0x$($hwnd.ToString('X'))"
[Win32]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 1000

# Run test
try {
    & "$PSScriptRoot\test-08-profile-menu.ps1" -Hwnd $hwnd -ProcessId $proc.Id
} finally {
    Stop-Ghostty -Process $proc
}
