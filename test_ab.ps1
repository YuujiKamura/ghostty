param(
    [string]$TestName = "unnamed",
    [string]$handlers = "true",
    [string]$close = "true",
    [string]$addtab = "true",
    [string]$selection = "true",
    [string]$append = "true",
    [string]$selectfirst = "true",
    [int]$WaitSec = 8
)

# Set env vars for the child process
$env:GHOSTTY_WINUI3_ENABLE_TABVIEW_HANDLERS = $handlers
$env:GHOSTTY_WINUI3_HANDLER_CLOSE = $close
$env:GHOSTTY_WINUI3_HANDLER_ADDTAB = $addtab
$env:GHOSTTY_WINUI3_HANDLER_SELECTION = $selection
$env:GHOSTTY_WINUI3_TABVIEW_APPEND_ITEM = $append
$env:GHOSTTY_WINUI3_TABVIEW_SELECT_FIRST = $selectfirst

Write-Host "=== TEST: $TestName ==="
Write-Host "  handlers=$handlers close=$close addtab=$addtab selection=$selection append=$append selectfirst=$selectfirst"

$repoRoot = Split-Path -Parent $PSCommandPath
$p = Start-Process -FilePath (Join-Path $repoRoot "zig-out\bin\ghostty.exe") -PassThru
Start-Sleep -Seconds $WaitSec

if ($p.HasExited) {
    $hex = "0x{0:X8}" -f $p.ExitCode
    Write-Host "  RESULT: CRASHED (ExitCode=$($p.ExitCode) / $hex)"
} else {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    Write-Host "  RESULT: STABLE (killed after ${WaitSec}s)"
}
