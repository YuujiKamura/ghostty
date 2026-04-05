<#
.SYNOPSIS
    UI throttling verification via deckpilot CP.
    Sends bulk output commands, checks UI responsiveness and CP round-trip.

.PARAMETER Lines
    Number of lines for bulk output (default: 50000)
.PARAMETER NoBuild
    Skip build step
#>
param(
    [int]$Lines = 50000,
    [switch]$NoBuild,
    [string]$ExePath = "zig-out-winui3\bin\ghostty.exe"
)

$ErrorActionPreference = "Continue"
$repoRoot = Split-Path -Parent $PSScriptRoot

# --- Prereqs ---
$deckpilot = Get-Command deckpilot -ErrorAction SilentlyContinue
if (-not $deckpilot) { Write-Error "deckpilot not found in PATH"; return }

if (-not $NoBuild) {
    Write-Host "[perf] Building..." -ForegroundColor Cyan
    Push-Location $repoRoot; bash -c "./build-winui3.sh" 2>&1 | Select-Object -Last 3; Pop-Location
}

$exe = if ([System.IO.Path]::IsPathRooted($ExePath)) { $ExePath } else { Join-Path $repoRoot $ExePath }
if (-not (Test-Path $exe)) { Write-Error "ghostty.exe not found at $exe"; return }

# --- Launch ---
Write-Host "[perf] Launching ghostty..." -ForegroundColor Cyan
$proc = Start-Process -FilePath $exe -PassThru
for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 1
    if ($proc.HasExited) { Write-Error "ghostty exited early"; return }
    $proc = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
    if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) { break }
}
if ($proc.MainWindowHandle -eq [IntPtr]::Zero) { Write-Error "No window"; return }

# Wait for CP session
Start-Sleep -Seconds 3
$session = (deckpilot list 2>&1 | Select-String "ghostty-$($proc.Id)" | ForEach-Object { ($_ -split '\s+')[0] })
if (-not $session) { Write-Error "CP session not found for PID $($proc.Id)"; return }
Write-Host "[perf] Session: $session" -ForegroundColor Green

# --- Pre-test: CP round-trip ---
Write-Host "`n[perf] Pre-test: CP echo..." -ForegroundColor Yellow
$preAck = deckpilot send $session 'echo PRE_CHECK' 2>&1
if ($preAck -notmatch 'ack') { Write-Error "CP pre-check failed: $preAck"; return }
Write-Host "  PASS: CP responsive" -ForegroundColor Green

# --- Baseline memory ---
$proc = Get-Process -Id $proc.Id
$startMem = [Math]::Round($proc.WorkingSet64 / 1MB, 1)
$startHandles = $proc.HandleCount

# --- Bulk output ---
Write-Host "`n[perf] Sending: yes | head -$Lines ..." -ForegroundColor Yellow
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$bulkAck = deckpilot send $session "yes | head -$Lines" 2>&1
$sw.Stop()
Write-Host "  deckpilot ack: $bulkAck (${$sw.ElapsedMilliseconds}ms)"

# Wait for output to complete
$waitSec = [Math]::Max(5, [Math]::Min(30, $Lines / 5000))
Write-Host "  Waiting ${waitSec}s for output to flush..." -ForegroundColor Gray

$notResponding = $false
for ($i = 0; $i -lt $waitSec; $i++) {
    Start-Sleep -Seconds 1
    if ($proc.HasExited) { break }
    $proc = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
    if ($proc -and -not $proc.Responding) { $notResponding = $true }
}

# --- Post-test: CP round-trip ---
Write-Host "`n[perf] Post-test: CP echo after bulk..." -ForegroundColor Yellow
$postAck = deckpilot send $session 'echo POST_CHECK' 2>&1
$cpAlive = $postAck -match 'ack'
if ($cpAlive) {
    Write-Host "  PASS: CP still responsive after $Lines lines" -ForegroundColor Green
} else {
    Write-Host "  FAIL: CP unresponsive: $postAck" -ForegroundColor Red
}

# --- End state ---
$crashed = $proc.HasExited
$endMem = if (-not $crashed) {
    $proc = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
    [Math]::Round($proc.WorkingSet64 / 1MB, 1)
} else { "N/A" }
$endHandles = if (-not $crashed) { $proc.HandleCount } else { "N/A" }

# --- Results ---
Write-Host "`n============================================" -ForegroundColor White
Write-Host "  PERF VERIFICATION" -ForegroundColor White
Write-Host "============================================" -ForegroundColor White
Write-Host "  Bulk lines:     $Lines"
Write-Host "  Memory:         $startMem -> $endMem MB"
Write-Host "  Handles:        $startHandles -> $endHandles"
Write-Host "  Crashed:        $crashed"
Write-Host "  Not Responding: $notResponding"
Write-Host "  CP post-check:  $(if ($cpAlive) { 'PASS' } else { 'FAIL' })"

$pass = (-not $crashed) -and $cpAlive -and (-not $notResponding)
if ($pass) {
    Write-Host "`n  VERDICT: PASS" -ForegroundColor Green
} else {
    Write-Host "`n  VERDICT: FAIL" -ForegroundColor Red
}

# Cleanup
if (-not $proc.HasExited) {
    $proc.CloseMainWindow() | Out-Null
    Start-Sleep -Seconds 2
    if (-not $proc.HasExited) { $proc.Kill() }
}
Write-Host ""
