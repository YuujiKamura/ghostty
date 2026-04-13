# Gemini CLI IME positioning test
$logFile = "gemini-ime-test.log"

Write-Host "=== Gemini CLI IME Positioning Test ===" -ForegroundColor Green
Write-Host "Testing Phase 3 effectiveness with Gemini CLI rapid cursor updates" -ForegroundColor Yellow

# Start Ghostty
Write-Host "`nStarting Ghostty..." -ForegroundColor Cyan
$process = Start-Process -FilePath ".\zig-out-winui3\bin\ghostty.exe" -RedirectStandardError $logFile -NoNewWindow -PassThru

Write-Host "Ghostty started (PID: $($process.Id))" -ForegroundColor Green
Write-Host "`nTest sequence:" -ForegroundColor Yellow
Write-Host "1. Wait 3 seconds for startup" -ForegroundColor White
Start-Sleep -Seconds 3

Write-Host "2. Testing with Gemini CLI - observing coordinate behavior" -ForegroundColor White
Write-Host "   Note: Gemini CLI creates rapid cursor updates that trigger TSF coordinate storms" -ForegroundColor Gray
Write-Host "   Phase 3 should stabilize these with coordinate caching" -ForegroundColor Gray

Write-Host "`nWaiting 15 seconds for Gemini CLI testing..." -ForegroundColor Magenta
Write-Host "Manual steps:" -ForegroundColor Cyan
Write-Host "- Type: gemini" -ForegroundColor White
Write-Host "- Test Japanese IME: こんにちは (konnichiwa)" -ForegroundColor White
Write-Host "- Observe IME positioning relative to cursor" -ForegroundColor White
Write-Host "- Check if composition text appears inline (good) or at screen corners (bad)" -ForegroundColor White

Start-Sleep -Seconds 15

# Kill the process
Write-Host "`nStopping Ghostty..." -ForegroundColor Yellow
Stop-Process -Id $process.Id -Force

# Analyze results
if (Test-Path $logFile) {
    Write-Host "`n=== Gemini CLI IME Analysis ===" -ForegroundColor Green

    $content = Get-Content $logFile -Encoding UTF8
    $cached = $content | Where-Object { $_ -match "\[CACHED\]" }
    $updated = $content | Where-Object { $_ -match "\[UPDATED\]" }
    $stabilized = $content | Where-Object { $_ -match "\[STABILIZED\]" }
    $tsf_calls = $content | Where-Object { $_ -match "TSF GetTextExt" }

    Write-Host "Coordinate caching metrics:" -ForegroundColor Yellow
    Write-Host "  Total TSF GetTextExt calls: $($tsf_calls.Count)" -ForegroundColor White
    Write-Host "  Cache hits [CACHED]: $($cached.Count)" -ForegroundColor Green
    Write-Host "  Cache updates [UPDATED]: $($updated.Count)" -ForegroundColor Yellow
    Write-Host "  Stabilized coords [STABILIZED]: $($stabilized.Count)" -ForegroundColor Blue

    if ($tsf_calls.Count -gt 0) {
        $cache_efficiency = [math]::Round(($cached.Count / $tsf_calls.Count) * 100, 1)
        Write-Host "  Cache efficiency: $cache_efficiency%" -ForegroundColor Cyan

        if ($cache_efficiency -gt 30) {
            Write-Host "`n✅ PHASE 3 SUCCESS: High cache efficiency indicates coordinate stability" -ForegroundColor Green
        } elseif ($cache_efficiency -gt 10) {
            Write-Host "`n⚠️ PARTIAL SUCCESS: Moderate caching, some improvement" -ForegroundColor Yellow
        } else {
            Write-Host "`n❌ MINIMAL IMPROVEMENT: Low cache efficiency" -ForegroundColor Red
        }
    }

    # Look for specific cursor positions that indicate Gemini CLI behavior
    $cursor_positions = $content | Where-Object { $_ -match "cursor=\((\d+),(\d+)\)" } | ForEach-Object {
        if ($_ -match "cursor=\((\d+),(\d+)\)") {
            "$($matches[1]),$($matches[2])"
        }
    }

    if ($cursor_positions) {
        $unique_positions = $cursor_positions | Sort-Object | Get-Unique
        Write-Host "`nCursor position analysis:" -ForegroundColor Yellow
        Write-Host "  Unique cursor positions: $($unique_positions.Count)" -ForegroundColor White
        if ($unique_positions.Count -gt 5) {
            Write-Host "  ⚠️ High position variance detected (Gemini-like behavior)" -ForegroundColor Yellow
        } else {
            Write-Host "  ✅ Stable cursor positioning detected" -ForegroundColor Green
        }
    }

    Write-Host "`nFull log saved: $logFile" -ForegroundColor Gray
    Write-Host "Run 'analyze-ime-logs.ps1 -LogFile $logFile -Analyze' for detailed analysis" -ForegroundColor Gray
}