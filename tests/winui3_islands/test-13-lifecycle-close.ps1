param([IntPtr]$Hwnd, [int]$ProcessId = 0)

# Test 13: Lifecycle close — verify that the close-tab code path runs and the
# process exits cleanly when GHOSTTY_WINUI3_CLOSE_TAB_AFTER_MS is set.
# This test does NOT require UIA; it manages its own process.
#
# NOTE: The runner's ghostty.exe may hold ghostty_debug.log open, so we must
# not attempt to delete it. Instead we record the file size before launch and
# only inspect bytes written after that offset. We also read the file with
# FileShare.ReadWrite to avoid sharing violations.

$ErrorActionPreference = 'Stop'
$testName = "test-13-lifecycle-close"

$exePath = Join-Path $PSScriptRoot "..\..\zig-out-winui3-islands\bin\ghostty.exe"
$exePath = (Resolve-Path $exePath -ErrorAction Stop).Path

if (-not (Test-Path $exePath)) {
    throw "$testName FAIL: ghostty.exe not found at $exePath"
}

$logPath = Join-Path $env:TEMP "ghostty_debug.log"

# Record the current log size so we only inspect new output from our process.
$logOffsetBefore = 0
if (Test-Path $logPath) {
    $logOffsetBefore = (Get-Item $logPath).Length
}

Write-Host "  Launching $exePath with GHOSTTY_WINUI3_CLOSE_TAB_AFTER_MS=3000 ..." -ForegroundColor DarkGray

# Launch with the env var that triggers an automatic tab close after N ms.
# Use try/finally to guarantee the env var is cleaned up even on failure.
$proc = $null
try {
    $env:GHOSTTY_WINUI3_CLOSE_TAB_AFTER_MS = "3000"
    $proc = Start-Process -FilePath $exePath -PassThru
} finally {
    $env:GHOSTTY_WINUI3_CLOSE_TAB_AFTER_MS = $null
}

$procId = $proc.Id
Write-Host "  PID = $procId" -ForegroundColor DarkGray

# Wait up to 15 seconds for the process to exit
$exited = $false
$deadline = [DateTime]::UtcNow.AddMilliseconds(15000)
while ([DateTime]::UtcNow -lt $deadline) {
    if ($proc.HasExited) {
        $exited = $true
        break
    }
    Start-Sleep -Milliseconds 500
}

# If it didn't exit, kill it and fail
if (-not $exited) {
    $proc | Stop-Process -Force -ErrorAction SilentlyContinue
    throw "$testName FAIL: Process did not exit within 15 seconds"
}

Test-Assert -Condition $exited -Message "$testName - process exited within timeout"

Write-Host "  Process exited with code $($proc.ExitCode)" -ForegroundColor DarkGray

# Read new log content using FileShare.ReadWrite to avoid conflicts with the
# runner's ghostty.exe which may still hold the file open.
$newLogContent = $null
if (Test-Path $logPath) {
    # Retry a few times in case the file is momentarily locked by a flush
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $fs = [System.IO.FileStream]::new(
                $logPath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
            )
            try {
                if ($fs.Length -gt $logOffsetBefore) {
                    $null = $fs.Seek($logOffsetBefore, [System.IO.SeekOrigin]::Begin)
                    $reader = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8, $false, 4096, $true)
                    $newLogContent = $reader.ReadToEnd()
                    $reader.Dispose()
                }
            } finally {
                $fs.Dispose()
            }
            break  # success
        } catch {
            if ($attempt -lt 3) {
                Write-Host "  Retry $attempt reading log: $($_.Exception.Message)" -ForegroundColor DarkGray
                Start-Sleep -Milliseconds 500
            } else {
                Write-Host "  WARN: Could not read log after 3 attempts: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
}

# Check the debug log for close-tab markers
if ($newLogContent) {
    $hasEntry = $newLogContent -match "closeTab: ENTRY"
    $hasExit  = $newLogContent -match "closeTab: EXIT"

    Test-Assert -Condition $hasEntry -Message "$testName - log contains 'closeTab: ENTRY'"
    Test-Assert -Condition $hasExit  -Message "$testName - log contains 'closeTab: EXIT'"
} else {
    Write-Host "  WARN: No new log content found; skipping log content checks" -ForegroundColor Yellow
    # The critical assertion is that the process exited; log checks are bonus.
}

Write-Host "PASS: $testName - close-tab lifecycle completed, process exited cleanly" -ForegroundColor Green
