# IME Log Capture Script for Phase 1 Analysis
# Captures detailed TSF/IME logs during Gemini CLI and Claude Code usage

param(
    [string]$LogFile = "ime-analysis-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
)

Write-Host "=== IME Log Capture for Phase 1 Analysis ===" -ForegroundColor Green
Write-Host "Log file: $LogFile" -ForegroundColor Yellow

# Create log capture function
function Start-GhosttyWithLogging {
    Write-Host "`nStarting Ghostty with detailed logging..." -ForegroundColor Yellow
    Write-Host "Log patterns to watch for:" -ForegroundColor Cyan
    Write-Host "  [TSF GetTextExt] - Coordinate requests from IME" -ForegroundColor Gray
    Write-Host "  [imePoint] - Surface coordinate calculation" -ForegroundColor Gray
    Write-Host "  [TUI cursor] - Cursor movement commands" -ForegroundColor Gray
    Write-Host "  [IME composition] - IME position updates" -ForegroundColor Gray
    Write-Host "  [TSF: OnStart/Update/End] - Composition lifecycle" -ForegroundColor Gray

    Write-Host "`nTest sequence:" -ForegroundColor Magenta
    Write-Host "  1. Wait for Ghostty to fully load" -ForegroundColor White
    Write-Host "  2. Type 'gemini' to launch Gemini CLI" -ForegroundColor White
    Write-Host "  3. Try Japanese IME input (e.g., 'konnichiha' -> こんにちは)" -ForegroundColor White
    Write-Host "  4. Note coordinate behavior in log output" -ForegroundColor White
    Write-Host "  5. Exit Gemini CLI (Ctrl+C or exit command)" -ForegroundColor White
    Write-Host "  6. Type 'claude-code' to launch Claude Code" -ForegroundColor White
    Write-Host "  7. Try the same Japanese IME input" -ForegroundColor White
    Write-Host "  8. Compare coordinate patterns" -ForegroundColor White
    Write-Host "  9. Press Ctrl+C in this PowerShell to stop logging" -ForegroundColor White

    Write-Host "`nStarting Ghostty and log capture..." -ForegroundColor Green
    & ".\zig-out-winui3\bin\ghostty.exe" 2>&1 | Tee-Object -FilePath $LogFile
}

try {
    Start-GhosttyWithLogging
}
catch {
    Write-Host "Error during log capture: $_" -ForegroundColor Red
}
finally {
    if (Test-Path $LogFile) {
        Write-Host "`nLog file created: $LogFile" -ForegroundColor Green
        $size = (Get-Item $LogFile).Length
        Write-Host "Log size: $size bytes" -ForegroundColor Yellow

        # Show last few lines of log
        Write-Host "`nLast 10 lines of log:" -ForegroundColor Cyan
        Get-Content $LogFile -Tail 10
    }
}