param(
    [string]$OutFile = "C:\Users\yuuji\ghostty-win\visual_smoke_test_new.png",
    [string]$AuditLog = "C:\Users\yuuji\ghostty-win\multitab_audit.log",
    [string]$DebugLog = "C:\Users\yuuji\ghostty-win\debug.log",
    [int]$WaitSec = 8,
    [ValidateSet("winui3","win32")][string]$Runtime = "winui3",
    [switch]$NoBuild,
    [switch]$FailOnWinRTHresult,
    [int]$MaxWinRTHresultCount = 0
)

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $repoRoot "scripts\winui3-test-lib.ps1")

# Set environment variables (allow caller override).
if (-not $env:GHOSTTY_WINUI3_ENABLE_TABVIEW) {
    $env:GHOSTTY_WINUI3_ENABLE_TABVIEW = "true"
}
if (-not $env:GHOSTTY_WINUI3_ENABLE_TABVIEW_HANDLERS) {
    $env:GHOSTTY_WINUI3_ENABLE_TABVIEW_HANDLERS = "true"
}

# Build and stage runtime-specific binary to avoid zig-out mixups.
$exePath = Get-StagedGhosttyExePath -RepoRoot $repoRoot -Runtime $Runtime
if (-not $NoBuild) {
    Write-Host "Building and staging Ghostty ($Runtime)..."
    $exePath = Build-AndStageGhosttyExe -RepoRoot $repoRoot -Runtime $Runtime
} elseif (-not (Test-Path $exePath)) {
    throw "No staged runtime binary found: $exePath (run without -NoBuild first)"
}

# Ensure old log is gone
if (Test-Path $AuditLog) { Remove-Item $AuditLog }
if (Test-Path $DebugLog) { Remove-Item $DebugLog }

Write-Host "Starting Ghostty for visual smoke test (Audit Mode)..."
# Redirect stderr to AuditLog
$p = Start-Process -FilePath $exePath -RedirectStandardError $AuditLog -PassThru
Start-Sleep -Seconds $WaitSec

Write-Host "Capturing screenshot..."
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$Screen = [System.Windows.Forms.Screen]::PrimaryScreen
$Bitmap = New-Object System.Drawing.Bitmap($Screen.Bounds.Width, $Screen.Bounds.Height)
$Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
$Graphics.CopyFromScreen($Screen.Bounds.X, $Screen.Bounds.Y, 0, 0, $Bitmap.Size)
$Bitmap.Save($OutFile)
$Graphics.Dispose()
$Bitmap.Dispose()
Write-Host "Screenshot saved to $OutFile"

if (!$p.HasExited) {
    Write-Host "Stopping Ghostty process..."
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "Ghostty exited prematurely with code $($p.ExitCode)"
}

# Runtime assertion from audit log (fail fast if wrong runtime launched).
if (Test-Path $AuditLog) {
    $expected = if ($Runtime -eq "winui3") { "runtime=.winui3" } else { "runtime=.win32" }
    $matches = Select-String -Path $AuditLog -Pattern $expected -SimpleMatch
    if (-not $matches) {
        throw "Runtime mismatch: expected '$expected' in $AuditLog"
    }
    Write-Host "Runtime assertion passed: $expected"
}

# Optional WinRT HRESULT audit (from debug.log).
if (Test-Path $DebugLog) {
    $pattern = "WinRT HRESULT failed: 0x80004002"
    $count = (Select-String -Path $DebugLog -Pattern $pattern -SimpleMatch | Measure-Object).Count
    Write-Host "WinRT HRESULT 0x80004002 count: $count"
    if ($FailOnWinRTHresult -and $count -gt $MaxWinRTHresultCount) {
        throw "WinRT HRESULT audit failed: count=$count threshold=$MaxWinRTHresultCount"
    }
}
