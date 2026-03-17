#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Ghosttyコントロールプレーン経由でClaude Codeの/usageダイアログの中身を取得する
.DESCRIPTION
  1. 新タブを開く
  2. claudeを起動
  3. /usageを送信
  4. TAILでダイアログ内容を取得
  5. クリーンアップして終了
.PARAMETER SessionName
  対象のGhosttyセッション名。省略時は最初に見つかったセッションを使用
.PARAMETER Runtime
  winui3 or win32 (default: winui3)
#>
param(
    [string]$SessionName = '',
    [ValidateSet('winui3', 'win32')]
    [string]$Runtime = 'winui3'
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
. "$ScriptDir\control-plane-session-lib.ps1"

# --- Session discovery ---
$root = Join-Path $env:LOCALAPPDATA "ghostty\control-plane\$Runtime\sessions"
if (-not (Test-Path $root)) {
    Write-Error "No $Runtime session registry found at: $root"
    exit 1
}

if ([string]::IsNullOrEmpty($SessionName)) {
    $sessions = Get-ChildItem $root -Filter '*.session' -ErrorAction SilentlyContinue
    if ($sessions.Count -eq 0) {
        Write-Error "No active $Runtime sessions found. Start Ghostty first."
        exit 1
    }
    $sessionFile = $sessions[0]
    $SessionName = ($sessionFile.BaseName -replace '-\d+$', '')
    Write-Host "Auto-selected session: $SessionName" -ForegroundColor Cyan
}

# --- Helper: send command and get response ---
function Send-ControlPlane {
    param([string]$Message, [string]$PipePath)

    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', $PipePath, [System.IO.Pipes.PipeDirection]::InOut)
    try {
        $pipe.Connect(5000)
        $pipe.ReadMode = [System.IO.Pipes.PipeTransmissionMode]::Message

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Message + "`r`n")
        $pipe.Write($bytes, 0, $bytes.Length)
        $pipe.Flush()

        $buffer = New-Object byte[] 65536
        $read = $pipe.Read($buffer, 0, $buffer.Length)
        return [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read).TrimEnd()
    }
    finally {
        $pipe.Dispose()
    }
}

# --- Resolve pipe path ---
$sessionEntry = Find-ControlPlaneSessionEntry -Root $root -SessionName $SessionName
if (-not $sessionEntry) {
    Write-Error "Session not found: $SessionName"
    exit 1
}
$pipeName = $sessionEntry.pipe_name
Write-Host "Using pipe: $pipeName" -ForegroundColor DarkGray

# --- Step 1: Open new tab ---
Write-Host "Opening new tab..." -ForegroundColor Yellow
$newTabResult = Send-ControlPlane -Message 'NEW_TAB' -PipePath $pipeName
Write-Host "  Result: $newTabResult" -ForegroundColor DarkGray

# Get tab count to know which tab we're on
Start-Sleep -Milliseconds 1000
$listResult = Send-ControlPlane -Message 'LIST_TABS' -PipePath $pipeName
Write-Host "  Tabs: $listResult" -ForegroundColor DarkGray

# Parse tab count - switch to the new (last) tab
if ($listResult -match 'tab_count=(\d+)') {
    $tabCount = [int]$Matches[1]
    $newTabIndex = $tabCount - 1
} else {
    $newTabIndex = 1  # fallback
}

# Switch to new tab
Send-ControlPlane -Message "SWITCH_TAB|$newTabIndex" -PipePath $pipeName | Out-Null
Start-Sleep -Milliseconds 500

# --- Step 2: Launch claude ---
Write-Host "Launching claude..." -ForegroundColor Yellow
$claudeCmd = "claude`r`n"
$b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($claudeCmd))
Send-ControlPlane -Message "RAW_INPUT|usage-check|$b64" -PipePath $pipeName | Out-Null

# Wait for claude to start (watch for prompt)
$maxWait = 30
$started = $false
for ($i = 0; $i -lt $maxWait; $i++) {
    Start-Sleep -Seconds 1
    $tail = Send-ControlPlane -Message 'TAIL|30' -PipePath $pipeName
    if ($tail -match '>' -or $tail -match 'claude' -or $tail -match '\$') {
        # Check if claude interactive prompt is visible
        if ($tail -match '>' -and $tail -notmatch 'command not found') {
            $started = $true
            Write-Host "  Claude started ($($i+1)s)" -ForegroundColor Green
            break
        }
    }
    Write-Host "  Waiting... ($($i+1)s)" -ForegroundColor DarkGray
}

if (-not $started) {
    Write-Warning "Claude may not have started. Continuing anyway..."
}

# --- Step 3: Send /usage ---
Write-Host "Sending /usage..." -ForegroundColor Yellow
$usageCmd = "/usage`r`n"
$b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($usageCmd))
Send-ControlPlane -Message "RAW_INPUT|usage-check|$b64" -PipePath $pipeName | Out-Null

# --- Step 4: Wait for dialog and capture ---
Start-Sleep -Seconds 3
Write-Host "Capturing dialog content..." -ForegroundColor Yellow

$usageContent = $null
for ($i = 0; $i -lt 5; $i++) {
    Start-Sleep -Seconds 1
    $tail = Send-ControlPlane -Message 'TAIL|50' -PipePath $pipeName

    # Look for usage dialog indicators
    if ($tail -match 'usage|Usage|limit|Limit|remaining|Remaining|percent|%|quota|Quota|subscription|Subscription') {
        $usageContent = $tail
        Write-Host "  Dialog captured!" -ForegroundColor Green
        break
    }
    Write-Host "  Polling... ($($i+1))" -ForegroundColor DarkGray
}

if (-not $usageContent) {
    # Grab whatever is on screen anyway
    $usageContent = Send-ControlPlane -Message 'TAIL|50' -PipePath $pipeName
    Write-Host "  Grabbed screen content (dialog may have been missed)" -ForegroundColor DarkYellow
}

# --- Step 5: Dismiss dialog (Enter) ---
$enter = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("`r"))
Send-ControlPlane -Message "RAW_INPUT|usage-check|$enter" -PipePath $pipeName | Out-Null
Start-Sleep -Milliseconds 500

# --- Step 6: Exit claude ---
Write-Host "Exiting claude..." -ForegroundColor Yellow
$exitCmd = "/exit`r`n"
$b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($exitCmd))
Send-ControlPlane -Message "RAW_INPUT|usage-check|$b64" -PipePath $pipeName | Out-Null
Start-Sleep -Seconds 2

# --- Step 7: Close tab ---
Write-Host "Closing tab..." -ForegroundColor Yellow
Send-ControlPlane -Message "CLOSE_TAB|$newTabIndex" -PipePath $pipeName | Out-Null

# --- Output ---
Write-Host ""
Write-Host "========== USAGE INFO ==========" -ForegroundColor Cyan
Write-Host $usageContent
Write-Host "================================" -ForegroundColor Cyan

# --- Save to file for programmatic access ---
$outputFile = Join-Path $env:LOCALAPPDATA 'ghostty\control-plane\claude-usage-latest.txt'
$usageContent | Out-File -FilePath $outputFile -Encoding utf8
Write-Host ""
Write-Host "Saved to: $outputFile" -ForegroundColor Green
