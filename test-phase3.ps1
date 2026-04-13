# Direct Phase 3 verification test
$logFile = "phase3-direct-test.log"

Write-Host "=== Phase 3 Direct Test ===" -ForegroundColor Green
Write-Host "Testing IME coordinate caching with manual verification" -ForegroundColor Yellow

Write-Host "`nStarting Ghostty with logging..." -ForegroundColor Cyan

# Start Ghostty and capture logs
$process = Start-Process -FilePath ".\zig-out-winui3\bin\ghostty.exe" -RedirectStandardError $logFile -NoNewWindow -PassThru

Write-Host "Ghostty started (PID: $($process.Id))" -ForegroundColor Green
Write-Host "`nManual test steps:" -ForegroundColor Yellow
Write-Host "1. Wait 3 seconds for startup" -ForegroundColor White
Write-Host "2. Type: gemini" -ForegroundColor White
Write-Host "3. Test Japanese IME: こんにちは" -ForegroundColor White
Write-Host "4. Check coordinate caching in logs" -ForegroundColor White

# Wait for startup
Start-Sleep -Seconds 3

Write-Host "`nWaiting 10 seconds for manual IME testing..." -ForegroundColor Magenta
Start-Sleep -Seconds 10

# Kill the process
Stop-Process -Id $process.Id -Force

# Analyze logs
if (Test-Path $logFile) {
    Write-Host "`n=== Phase 3 Log Analysis ===" -ForegroundColor Green

    $content = Get-Content $logFile -Encoding UTF8
    $cached = $content | Where-Object { $_ -match "\[CACHED\]" }
    $updated = $content | Where-Object { $_ -match "\[UPDATED\]" }
    $stabilized = $content | Where-Object { $_ -match "\[STABILIZED\]" }
    $tsf_calls = $content | Where-Object { $_ -match "TSF GetTextExt" }

    Write-Host "Results:" -ForegroundColor Yellow
    Write-Host "  Total TSF GetTextExt calls: $($tsf_calls.Count)" -ForegroundColor White
    Write-Host "  Cache hits [CACHED]: $($cached.Count)" -ForegroundColor Green
    Write-Host "  Cache updates [UPDATED]: $($updated.Count)" -ForegroundColor Yellow
    Write-Host "  Stabilized coords [STABILIZED]: $($stabilized.Count)" -ForegroundColor Blue

    if ($cached.Count -gt 0 -or $stabilized.Count -gt 0) {
        Write-Host "`n✅ Phase 3 coordinate caching IS WORKING" -ForegroundColor Green
        if ($cached.Count -gt 0) {
            Write-Host "Sample cache hit:" -ForegroundColor Gray
            $cached[0] | Write-Host -ForegroundColor Gray
        }
    } else {
        Write-Host "`n⚠️  No cache activity detected" -ForegroundColor Red
        if ($tsf_calls.Count -eq 0) {
            Write-Host "No TSF calls detected - IME may not have been used" -ForegroundColor Yellow
        }
    }

    Write-Host "`nFull log saved: $logFile" -ForegroundColor Gray
}