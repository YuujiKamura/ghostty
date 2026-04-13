# Test script for Phase 1 & 2 IME improvements
# Tests debug logging and coordinate calculation fixes

param(
    [string]$GhosttyExe = ".\zig-out-winui3\ghostty.exe"
)

Write-Host "=== Testing Ghostty IME Improvements (Phase 1 & 2) ===" -ForegroundColor Green

# Check if ghostty.exe exists
if (-not (Test-Path $GhosttyExe)) {
    Write-Host "ERROR: $GhosttyExe not found!" -ForegroundColor Red
    exit 1
}

Write-Host "1. Checking Ghostty version and build timestamp..." -ForegroundColor Yellow
& $GhosttyExe --version

Write-Host "`n2. Starting Ghostty for IME testing..." -ForegroundColor Yellow
Write-Host "Instructions for manual testing:" -ForegroundColor Cyan
Write-Host "  - Launch Gemini CLI: 'gemini'" -ForegroundColor White
Write-Host "  - Try Japanese IME input (ひらがな)" -ForegroundColor White
Write-Host "  - Launch Claude Code: 'claude-code'" -ForegroundColor White
Write-Host "  - Try Japanese IME input again" -ForegroundColor White
Write-Host "  - Check console output for detailed logs" -ForegroundColor White
Write-Host "  - Press Ctrl+C when done testing" -ForegroundColor White

Write-Host "`nPhase 1 Expected Logs:" -ForegroundColor Magenta
Write-Host "  - 'TSF GetTextExt: cursor=(...) ime_pos=(...) ...' - TSF coordinate calculation" -ForegroundColor Gray
Write-Host "  - 'imePoint: cursor=(...) cell=(...) ...' - Surface coordinate calculation" -ForegroundColor Gray
Write-Host "  - 'TUI cursor update: CSI H (...)' - Cursor movement tracking" -ForegroundColor Gray
Write-Host "  - 'TSF: OnStartComposition' - IME composition events" -ForegroundColor Gray

Write-Host "`nPhase 2 Expected Improvements:" -ForegroundColor Magenta
Write-Host "  - Reduced coordinate 'jitter' or inconsistency" -ForegroundColor Gray
Write-Host "  - More stable IME positioning with Gemini CLI" -ForegroundColor Gray

Write-Host "`nStarting Ghostty..." -ForegroundColor Yellow
& $GhosttyExe