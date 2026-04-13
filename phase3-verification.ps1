# Phase 3 Verification Script - IME Coordinate Caching Test

$logFile = "phase3-test-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

Write-Host "=== Phase 3 Verification Test ===" -ForegroundColor Green
Write-Host "Testing IME coordinate caching and stabilization" -ForegroundColor Yellow
Write-Host "Log file: $logFile" -ForegroundColor Gray

Write-Host "`nExpected Phase 3 log patterns:" -ForegroundColor Cyan
Write-Host "  [CACHED] - Using cached coordinates (stability working)" -ForegroundColor Green
Write-Host "  [UPDATED] - Updating cache with new coordinates" -ForegroundColor Yellow
Write-Host "  [STABILIZED] - Ignoring small coordinate changes" -ForegroundColor Blue

Write-Host "`nTest sequence:" -ForegroundColor Magenta
Write-Host "1. Wait for Ghostty startup" -ForegroundColor White
Write-Host "2. Type: gemini" -ForegroundColor White
Write-Host "3. Try Japanese IME: 'konnichiha' -> こんにちは" -ForegroundColor White
Write-Host "4. Observe IME positioning and logs" -ForegroundColor White
Write-Host "5. Check for [CACHED]/[STABILIZED] patterns" -ForegroundColor White
Write-Host "6. Exit when done testing" -ForegroundColor White

Write-Host "`nStarting Ghostty with Phase 3 logging..." -ForegroundColor Green

try {
    & ".\zig-out-winui3\bin\ghostty.exe" 2>&1 | Tee-Object -FilePath $logFile
}
finally {
    if (Test-Path $logFile) {
        Write-Host "`n=== Phase 3 Log Analysis ===" -ForegroundColor Green

        $content = Get-Content $logFile
        $cached = $content | Where-Object { $_ -match "\[CACHED\]" }
        $updated = $content | Where-Object { $_ -match "\[UPDATED\]" }
        $stabilized = $content | Where-Object { $_ -match "\[STABILIZED\]" }
        $tsf_calls = $content | Where-Object { $_ -match "TSF GetTextExt" }

        Write-Host "Results:" -ForegroundColor Yellow
        Write-Host "  Total TSF GetTextExt calls: $($tsf_calls.Count)" -ForegroundColor White
        Write-Host "  Cache hits [CACHED]: $($cached.Count)" -ForegroundColor Green
        Write-Host "  Cache updates [UPDATED]: $($updated.Count)" -ForegroundColor Yellow
        Write-Host "  Stabilized coords [STABILIZED]: $($stabilized.Count)" -ForegroundColor Blue

        if ($cached.Count -gt 0) {
            Write-Host "`n✅ Phase 3 coordinate caching is WORKING" -ForegroundColor Green
        } else {
            Write-Host "`n⚠️ No cache hits detected - may need more testing" -ForegroundColor Red
        }

        if ($stabilized.Count -gt 0) {
            Write-Host "✅ Coordinate stabilization is WORKING" -ForegroundColor Green
        }

        Write-Host "`nCache efficiency: $([math]::Round(($cached.Count / [math]::Max($tsf_calls.Count, 1)) * 100, 1))%" -ForegroundColor Cyan

        Write-Host "`nLog saved: $logFile" -ForegroundColor Gray
    }
}