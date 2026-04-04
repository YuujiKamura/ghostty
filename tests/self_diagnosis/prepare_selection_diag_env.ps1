param(
  [switch]$KeepRunning
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$stableExe = Join-Path $repoRoot 'zig-out-winui3/bin/ghostty.exe'
$stagingDir = Join-Path $repoRoot 'zig-out-winui3-staging'
$sessionDir = Join-Path $env:LOCALAPPDATA 'ghostty/control-plane/winui3/sessions'

if (-not (Test-Path -LiteralPath $stableExe)) {
  throw "stable ghostty.exe not found: $stableExe"
}

# 1) Kill all running Ghostty processes to avoid mixed-session ambiguity.
$running = Get-Process -Name ghostty -ErrorAction SilentlyContinue
if ($running) {
  foreach ($p in $running) {
    try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch {}
  }
  Start-Sleep -Milliseconds 400
}

# 2) Remove staging output before diagnostics.
if (Test-Path -LiteralPath $stagingDir) {
  Remove-Item -LiteralPath $stagingDir -Recurse -Force
}

$stagingState = if (Test-Path -LiteralPath $stagingDir) { 'present' } else { 'absent' }

# 3) Launch canonical stable binary and resolve newest session metadata.
$proc = Start-Process -FilePath $stableExe -PassThru
Start-Sleep -Milliseconds 1200
$title = (Get-Process -Id $proc.Id).MainWindowTitle

$sessionFile = $null
if (Test-Path -LiteralPath $sessionDir) {
  $sessionFile = Get-ChildItem -LiteralPath $sessionDir -Filter '*.session' -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

$sessionName = ''
$pipePath = ''
if ($sessionFile) {
  $lines = Get-Content -LiteralPath $sessionFile.FullName
  foreach ($ln in $lines) {
    if ($ln -like 'session_name=*') { $sessionName = $ln.Substring(13).Trim() }
    if ($ln -like 'pipe_path=*') { $pipePath = $ln.Substring(10).Trim() }
  }
}

"stable_exe=$stableExe"
"launched_pid=$($proc.Id)"
"window_title=$title"
"staging_dir=$stagingState"
"session_file=$($sessionFile.Name)"
"session_name=$sessionName"
"pipe_path=$pipePath"

if (-not $KeepRunning) {
  try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop } catch {}
  "stopped_pid=$($proc.Id)"
}
