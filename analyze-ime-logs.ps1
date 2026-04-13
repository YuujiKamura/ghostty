# IME Log Analysis Script for identifying TSF coordinate issues
# Analyzes Phase 1 logs to identify Gemini CLI vs Claude Code behavior patterns

param(
    [string]$LogFile,
    [switch]$Analyze
)

if (-not $LogFile -or -not (Test-Path $LogFile)) {
    Write-Host "Usage: analyze-ime-logs.ps1 -LogFile <path> [-Analyze]" -ForegroundColor Yellow
    Write-Host "No log file specified or file not found. Starting log collection..." -ForegroundColor Yellow

    # Start log collection
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $newLogFile = "ime-logs-$timestamp.log"

    Write-Host "=== Starting IME Log Collection ===" -ForegroundColor Green
    Write-Host "Log file: $newLogFile" -ForegroundColor Yellow
    Write-Host "`nInstructions:" -ForegroundColor Cyan
    Write-Host "1. Wait for Ghostty to start" -ForegroundColor White
    Write-Host "2. Test sequence A - Gemini CLI:" -ForegroundColor Yellow
    Write-Host "   - Type: gemini" -ForegroundColor Gray
    Write-Host "   - Try Japanese IME: こんにちは" -ForegroundColor Gray
    Write-Host "   - Watch console for TSF coordinate logs" -ForegroundColor Gray
    Write-Host "   - Exit: Ctrl+C" -ForegroundColor Gray
    Write-Host "3. Test sequence B - Claude Code:" -ForegroundColor Yellow
    Write-Host "   - Type: claude-code" -ForegroundColor Gray
    Write-Host "   - Try the same Japanese IME input" -ForegroundColor Gray
    Write-Host "   - Compare coordinate behavior" -ForegroundColor Gray
    Write-Host "   - Exit: Ctrl+C" -ForegroundColor Gray
    Write-Host "4. Close Ghostty and analyze logs" -ForegroundColor White

    Write-Host "`nKey log patterns to watch for:" -ForegroundColor Magenta
    Write-Host "- TSF GetTextExt: rapid coordinate requests" -ForegroundColor Gray
    Write-Host "- imePoint: inconsistent cursor positions" -ForegroundColor Gray
    Write-Host "- TUI cursor update: excessive movement commands" -ForegroundColor Gray
    Write-Host "`nStarting Ghostty..." -ForegroundColor Green

    try {
        & ".\zig-out-winui3\bin\ghostty.exe" 2>&1 | Tee-Object -FilePath $newLogFile
    }
    finally {
        if (Test-Path $newLogFile) {
            Write-Host "`nLog collection completed: $newLogFile" -ForegroundColor Green
            Write-Host "Re-run with: analyze-ime-logs.ps1 -LogFile '$newLogFile' -Analyze" -ForegroundColor Yellow
        }
    }
    return
}

Write-Host "=== Analyzing IME Logs: $LogFile ===" -ForegroundColor Green

if (-not $Analyze) {
    Write-Host "Add -Analyze flag to perform detailed analysis" -ForegroundColor Yellow
    return
}

# Analysis functions
function Extract-TSFCoordinateEvents {
    param($content)
    $events = @()
    foreach ($line in $content) {
        if ($line -match "TSF GetTextExt.*cursor=\((\d+),(\d+)\).*ime_pos=\(([0-9.]+),([0-9.]+)\).*screen=\((-?\d+),(-?\d+)\)") {
            $events += [PSCustomObject]@{
                Type = "TSF_GetTextExt"
                Time = (Get-Date)
                CursorX = [int]$matches[1]
                CursorY = [int]$matches[2]
                ImePosX = [float]$matches[3]
                ImePosY = [float]$matches[4]
                ScreenX = [int]$matches[5]
                ScreenY = [int]$matches[6]
                RawLine = $line
            }
        }
        if ($line -match "imePoint.*cursor=\((\d+),(\d+)\).*scale=\(([0-9.]+),([0-9.]+)\).*result=\(([0-9.]+),([0-9.]+)\)") {
            $events += [PSCustomObject]@{
                Type = "imePoint_Calc"
                Time = (Get-Date)
                CursorX = [int]$matches[1]
                CursorY = [int]$matches[2]
                ScaleX = [float]$matches[3]
                ScaleY = [float]$matches[4]
                ResultX = [float]$matches[5]
                ResultY = [float]$matches[6]
                RawLine = $line
            }
        }
        if ($line -match "TUI cursor update: CSI H \((\d+),(\d+)\)") {
            $events += [PSCustomObject]@{
                Type = "Cursor_Update"
                Time = (Get-Date)
                Row = [int]$matches[1]
                Col = [int]$matches[2]
                RawLine = $line
            }
        }
    }
    return $events
}

function Analyze-CoordinatePatterns {
    param($events)

    Write-Host "`n=== Coordinate Pattern Analysis ===" -ForegroundColor Cyan

    $tsfEvents = $events | Where-Object { $_.Type -eq "TSF_GetTextExt" }
    $imeEvents = $events | Where-Object { $_.Type -eq "imePoint_Calc" }
    $cursorEvents = $events | Where-Object { $_.Type -eq "Cursor_Update" }

    Write-Host "Event counts:" -ForegroundColor Yellow
    Write-Host "  TSF GetTextExt calls: $($tsfEvents.Count)" -ForegroundColor White
    Write-Host "  imePoint calculations: $($imeEvents.Count)" -ForegroundColor White
    Write-Host "  Cursor updates: $($cursorEvents.Count)" -ForegroundColor White

    if ($tsfEvents.Count -gt 0) {
        Write-Host "`nTSF Coordinate Analysis:" -ForegroundColor Yellow
        $screenCoords = $tsfEvents | Group-Object { "$($_.ScreenX),$($_.ScreenY)" }
        Write-Host "  Unique screen positions: $($screenCoords.Count)" -ForegroundColor White

        if ($screenCoords.Count -gt 5) {
            Write-Host "  ⚠️  HIGH COORDINATE VARIANCE - Potential jitter detected!" -ForegroundColor Red
            $screenCoords | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object {
                Write-Host "    Position $($_.Name): $($_.Count) times" -ForegroundColor Gray
            }
        }

        # Check for rapid consecutive calls
        $rapidCalls = 0
        for ($i = 1; $i -lt $tsfEvents.Count; $i++) {
            if (($tsfEvents[$i].CursorX -ne $tsfEvents[$i-1].CursorX) -or
                ($tsfEvents[$i].CursorY -ne $tsfEvents[$i-1].CursorY)) {
                $rapidCalls++
            }
        }

        if ($rapidCalls -gt ($tsfEvents.Count * 0.3)) {
            Write-Host "  ⚠️  EXCESSIVE COORDINATE CHANGES - $rapidCalls changes in $($tsfEvents.Count) calls" -ForegroundColor Red
        }
    }

    return @{
        TSFEvents = $tsfEvents
        ImeEvents = $imeEvents
        CursorEvents = $cursorEvents
        HighVariance = $screenCoords.Count -gt 5
        ExcessiveChanges = $rapidCalls -gt ($tsfEvents.Count * 0.3)
    }
}

# Main analysis
try {
    $content = Get-Content $LogFile
    Write-Host "Log lines: $($content.Count)" -ForegroundColor Yellow

    $events = Extract-TSFCoordinateEvents $content
    Write-Host "Extracted events: $($events.Count)" -ForegroundColor Yellow

    if ($events.Count -eq 0) {
        Write-Host "⚠️  No TSF/IME events found in log. Ensure:" -ForegroundColor Red
        Write-Host "  - Japanese IME input was attempted" -ForegroundColor Gray
        Write-Host "  - Ghostty was built with Phase 1 logging" -ForegroundColor Gray
        Write-Host "  - Log level includes info messages" -ForegroundColor Gray
        return
    }

    $analysis = Analyze-CoordinatePatterns $events

    Write-Host "`n=== Phase 3 Recommendations ===" -ForegroundColor Green

    if ($analysis.HighVariance) {
        Write-Host "🔧 Implement coordinate caching:" -ForegroundColor Yellow
        Write-Host "   - Cache stable coordinates for 100-200ms" -ForegroundColor Gray
        Write-Host "   - Ignore minor position fluctuations (<5 pixels)" -ForegroundColor Gray
    }

    if ($analysis.ExcessiveChanges) {
        Write-Host "🔧 Implement update throttling:" -ForegroundColor Yellow
        Write-Host "   - Debounce TSF updates with 50ms delay" -ForegroundColor Gray
        Write-Host "   - Batch multiple cursor updates" -ForegroundColor Gray
    }

    if ($analysis.TSFEvents.Count -gt 20) {
        Write-Host "🔧 Reduce TSF call frequency:" -ForegroundColor Yellow
        Write-Host "   - Implement smart invalidation" -ForegroundColor Gray
        Write-Host "   - Only update on significant position changes" -ForegroundColor Gray
    }

    # Export detailed results
    $outputFile = $LogFile -replace "\.log$", "-analysis.json"
    $analysis | ConvertTo-Json -Depth 3 | Out-File $outputFile
    Write-Host "`nDetailed analysis saved: $outputFile" -ForegroundColor Green

} catch {
    Write-Host "Analysis error: $_" -ForegroundColor Red
}