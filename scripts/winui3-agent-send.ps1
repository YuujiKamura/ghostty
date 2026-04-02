<#
.SYNOPSIS
    High-level wrapper for sending commands to agent TUIs (codex, claude, gemini)
    running in Ghostty WinUI3 sessions.

.DESCRIPTION
    Wraps winui3-control-send.ps1 to provide agent-specific launch, send, and exit
    workflows. Each agent has different input/submit semantics handled internally.

    IMPORTANT: This script is PowerShell — text sent via INPUT is base64-encoded by
    the transport layer (winui3-control-send.ps1) and does NOT pass through MINGW bash
    path expansion. Always invoke with `pwsh.exe -File` to avoid shell interference.

.EXAMPLE
    # Launch codex in full-auto mode, wait for ready
    pwsh -File winui3-agent-send.ps1 -Agent codex -Action launch -Session dev -FullAuto -WaitForReady

    # Send a prompt to codex
    pwsh -File winui3-agent-send.ps1 -Agent codex -Action send -Session dev -Text "fix the build"

    # One-shot claude prompt (non-interactive, reliable)
    pwsh -File winui3-agent-send.ps1 -Agent claude -Action send -Session dev -Text "explain this code" -OneShot

    # Exit gemini
    pwsh -File winui3-agent-send.ps1 -Agent gemini -Action exit -Session dev
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('codex', 'claude', 'gemini')]
    [string]$Agent,

    [Parameter(Mandatory = $true)]
    [ValidateSet('launch', 'send', 'exit')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$Session,

    [string]$Text = '',

    [switch]$FullAuto,

    [switch]$OneShot,

    [switch]$WaitForReady,

    [int]$Timeout = 30
)

$ErrorActionPreference = 'Stop'

$controlSendScript = Join-Path $PSScriptRoot 'winui3-control-send.ps1'

# ---------------------------------------------------------------------------
# Transport helpers
# ---------------------------------------------------------------------------

function Send-Input {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionName,
        [Parameter(Mandatory = $true)]
        [string]$RawText
    )
    & pwsh -NoLogo -NoProfile -File $controlSendScript `
        -SessionName $SessionName -Type INPUT -From 'agent-send' -Text $RawText 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "INPUT failed for session '$SessionName'"
    }
}

function Send-RawInput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionName,
        [Parameter(Mandatory = $true)]
        [string]$RawText
    )
    & pwsh -NoLogo -NoProfile -File $controlSendScript `
        -SessionName $SessionName -Type RAW_INPUT -From 'agent-send' -Text $RawText 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "RAW_INPUT failed for session '$SessionName'"
    }
}

function Get-SessionState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionName
    )
    $raw = & pwsh -NoLogo -NoProfile -File $controlSendScript `
        -SessionName $SessionName -Type STATE 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return [string]$raw
}

function Get-SessionTail {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionName,
        [int]$Lines = 20
    )
    $raw = & pwsh -NoLogo -NoProfile -File $controlSendScript `
        -SessionName $SessionName -Type TAIL -Lines $Lines 2>$null
    if ($LASTEXITCODE -ne 0) { return '' }
    return [string]$raw
}

function Remove-AnsiEscapes {
    param([string]$Text)
    # Strip ANSI CSI sequences (ESC[...X) and OSC sequences (ESC]...BEL/ST)
    return $Text -replace '\x1b\[[0-9;]*[A-Za-z]', '' -replace '\x1b\][^\x07]*\x07', '' -replace '\x1b\][^\x1b]*\x1b\\', ''
}

function Wait-SessionReady {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionName,
        [int]$TimeoutSec = 30,
        [string]$AgentName = ''
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 1
        $state = Get-SessionState -SessionName $SessionName
        if ($null -eq $state) { continue }

        # Check if the agent prompt is visible in the tail (strip ANSI escapes first)
        $rawTail = Get-SessionTail -SessionName $SessionName -Lines 10
        $tail = Remove-AnsiEscapes -Text $rawTail
        $ready = $false

        switch ($AgentName) {
            'codex' {
                # codex shows ">" prompt when ready
                if ($tail -match '>\s*$') { $ready = $true }
            }
            'claude' {
                # claude shows ">" or the input area; also detect trust dialog
                if ($tail -match '>\s*$' -or $tail -match 'What would you like to do') {
                    $ready = $true
                }
            }
            'gemini' {
                # gemini shows "> Type your message" or ">" prompt
                if ($tail -match 'Type your message' -or $tail -match '>{1,3}\s*$') { $ready = $true }
            }
            default {
                # Generic: look for a prompt indicator in STATE
                if ($state -match 'prompt=1') { $ready = $true }
            }
        }

        if ($ready) { return $true }
    }
    return $false
}

function Send-CtrlC {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SessionName
    )
    # Ctrl+C is ASCII 0x03
    Send-Input -SessionName $SessionName -RawText ([char]3).ToString()
}

# ---------------------------------------------------------------------------
# Result builder
# ---------------------------------------------------------------------------

function New-AgentResult {
    param(
        [string]$Status = 'ok',
        [string]$AgentName,
        [string]$ActionName,
        [string]$Detail = ''
    )
    [pscustomobject]@{
        Status = $Status
        Agent  = $AgentName
        Action = $ActionName
        Detail = $Detail
    }
}

# ---------------------------------------------------------------------------
# Agent profiles — Launch
# ---------------------------------------------------------------------------

function Invoke-LaunchCodex {
    param([string]$SessionName, [switch]$FullAutoMode)

    $cmd = if ($FullAutoMode) { "codex --full-auto`r" } else { "codex`r" }
    Send-Input -SessionName $SessionName -RawText $cmd
    return 'launched codex' + $(if ($FullAutoMode) { ' (full-auto)' } else { '' })
}

function Invoke-LaunchClaude {
    param([string]$SessionName)

    # Step 1: Unset CLAUDECODE env var to avoid nested-session conflict
    # Ghostty's default shell is cmd.exe on Windows; use `set VAR=` syntax
    Send-Input -SessionName $SessionName -RawText "set CLAUDECODE=`r"
    Start-Sleep -Milliseconds 500

    # Step 2: Launch claude
    Send-Input -SessionName $SessionName -RawText "claude`r"

    # Step 3: Auto-handle trust dialog — poll for up to 15s since Claude startup is slow
    $trustDeadline = (Get-Date).AddSeconds(15)
    $trustHandled = $false
    while ((Get-Date) -lt $trustDeadline) {
        Start-Sleep -Seconds 2
        $rawTail = Get-SessionTail -SessionName $SessionName -Lines 15
        $tail = Remove-AnsiEscapes -Text $rawTail
        if ($tail -match 'trust this folder|Trust|Yes, I trust') {
            Send-Input -SessionName $SessionName -RawText '1'
            Start-Sleep -Milliseconds 500
            Send-Input -SessionName $SessionName -RawText "`r"
            $trustHandled = $true
            Start-Sleep -Seconds 3
            break
        }
        # Already past the trust dialog (e.g. previously trusted)
        if ($tail -match 'bypass permissions|What would you like') {
            $trustHandled = $true
            break
        }
    }

    return 'launched claude (trust dialog auto-handled)'
}

function Invoke-LaunchGemini {
    param([string]$SessionName)

    Send-Input -SessionName $SessionName -RawText "gemini`r"
    return 'launched gemini'
}

# ---------------------------------------------------------------------------
# Agent profiles — Send
# ---------------------------------------------------------------------------

function Invoke-SendCodex {
    param(
        [string]$SessionName,
        [string]$Prompt
    )

    # Step 1: Type the text into the input field
    Send-Input -SessionName $SessionName -RawText $Prompt
    Start-Sleep -Milliseconds 200

    # Step 2: Press Enter to submit (separate \r)
    Send-Input -SessionName $SessionName -RawText "`r"
    return "sent prompt to codex ($($Prompt.Length) chars)"
}

function Invoke-SendClaude {
    param(
        [string]$SessionName,
        [string]$Prompt,
        [switch]$OneShotMode
    )

    if ($OneShotMode) {
        # Reliable non-interactive path: claude -p "..." --max-turns 1
        # Ghostty's default shell is cmd.exe on Windows.
        # Always unset CLAUDECODE first to avoid nested-session rejection
        Send-Input -SessionName $SessionName -RawText "set CLAUDECODE=`r"
        Start-Sleep -Milliseconds 500
        # For long prompts or those with special chars, write to a temp file
        # and use powershell to read it (avoids cmd.exe escaping issues).
        if ($Prompt.Length -gt 4000 -or $Prompt -match '[\$`"\\!&|<>^%]') {
            $tmpFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "agent-send-$([guid]::NewGuid().ToString('N').Substring(0,8)).txt")
            try {
                [System.IO.File]::WriteAllText($tmpFile, $Prompt, [System.Text.Encoding]::UTF8)
                $winPath = $tmpFile -replace '/', '\'
                $cmd = "powershell -NoProfile -Command `"claude -p (Get-Content -Raw '$winPath') --max-turns 1; Remove-Item '$winPath' -Force`"`r"
                Send-Input -SessionName $SessionName -RawText $cmd
            } catch {
                if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue }
                throw "failed to write temp file for claude one-shot: $_"
            }
            return "sent one-shot prompt to claude via tempfile ($($Prompt.Length) chars)"
        }
        # Simple prompt: escape for cmd.exe double-quote context
        $escaped = $Prompt -replace '"', '\"'
        $cmd = "claude -p `"$escaped`" --max-turns 1`r"
        Send-Input -SessionName $SessionName -RawText $cmd
        return "sent one-shot prompt to claude ($($Prompt.Length) chars)"
    }

    # Interactive TUI mode: paste text via INPUT, submit via RAW_INPUT Enter
    Send-Input -SessionName $SessionName -RawText $Prompt
    Start-Sleep -Milliseconds 200
    Send-RawInput -SessionName $SessionName -RawText "`r"
    return "sent prompt to claude TUI ($($Prompt.Length) chars)"
}

function Invoke-SendGemini {
    param(
        [string]$SessionName,
        [string]$Prompt,
        [switch]$OneShotMode
    )

    if ($OneShotMode) {
        # Non-interactive: run gemini as a one-shot command on cmd.exe shell
        if ($Prompt.Length -gt 4000 -or $Prompt -match '[\$`"\\!&|<>^%]') {
            $tmpFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "agent-send-$([guid]::NewGuid().ToString('N').Substring(0,8)).txt")
            try {
                [System.IO.File]::WriteAllText($tmpFile, $Prompt, [System.Text.Encoding]::UTF8)
                $winPath = $tmpFile -replace '/', '\'
                $cmd = "powershell -NoProfile -Command `"Get-Content -Raw '$winPath' | gemini -o text; Remove-Item '$winPath' -Force`"`r"
                Send-Input -SessionName $SessionName -RawText $cmd
            } catch {
                if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue }
                throw "failed to write temp file for gemini: $_"
            }
            return "sent one-shot prompt to gemini via tempfile ($($Prompt.Length) chars)"
        }
        $escaped = $Prompt -replace '"', '\"'
        $cmd = "echo `"$escaped`" | gemini -o text`r"
        Send-Input -SessionName $SessionName -RawText $cmd
        return "sent one-shot prompt to gemini ($($Prompt.Length) chars)"
    }

    # Interactive TUI mode: paste text via INPUT, submit via RAW_INPUT Enter
    Send-Input -SessionName $SessionName -RawText $Prompt
    Start-Sleep -Milliseconds 200
    Send-RawInput -SessionName $SessionName -RawText "`r"
    return "sent prompt to gemini TUI ($($Prompt.Length) chars)"
}

# ---------------------------------------------------------------------------
# Agent profiles — Exit
# ---------------------------------------------------------------------------

function Invoke-ExitCodex {
    param(
        [string]$SessionName,
        [int]$TimeoutSec = 10
    )

    # Try /exit command first
    Send-Input -SessionName $SessionName -RawText "/exit`r"
    Start-Sleep -Milliseconds 500
    Send-Input -SessionName $SessionName -RawText "`r"
    Start-Sleep -Seconds 2

    # Check if still running
    $state = Get-SessionState -SessionName $SessionName
    if ($null -ne $state -and $state -match 'prompt=0') {
        # Still running, send Ctrl+C twice
        Send-CtrlC -SessionName $SessionName
        Start-Sleep -Milliseconds 500
        Send-CtrlC -SessionName $SessionName
        return 'exited codex (Ctrl+C fallback)'
    }

    return 'exited codex (/exit)'
}

function Invoke-ExitClaude {
    param(
        [string]$SessionName,
        [int]$TimeoutSec = 10
    )

    # Ctrl+C twice
    Send-CtrlC -SessionName $SessionName
    Start-Sleep -Milliseconds 500
    Send-CtrlC -SessionName $SessionName
    Start-Sleep -Seconds 2

    # Verify exit
    $state = Get-SessionState -SessionName $SessionName
    if ($null -ne $state -and $state -match 'prompt=0') {
        return 'exited claude (may still be shutting down)'
    }

    return 'exited claude'
}

function Invoke-ExitGemini {
    param([string]$SessionName)

    Send-CtrlC -SessionName $SessionName
    return 'exited gemini'
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------

$detail = ''
$status = 'ok'

try {
    switch ($Action) {
        'launch' {
            switch ($Agent) {
                'codex'  { $detail = Invoke-LaunchCodex  -SessionName $Session -FullAutoMode:$FullAuto }
                'claude' { $detail = Invoke-LaunchClaude -SessionName $Session }
                'gemini' { $detail = Invoke-LaunchGemini -SessionName $Session }
            }

            if ($WaitForReady) {
                $ready = Wait-SessionReady -SessionName $Session -TimeoutSec $Timeout -AgentName $Agent
                if (-not $ready) {
                    $status = 'timeout'
                    $detail += ' (wait-for-ready timed out)'
                } else {
                    $detail += ' (ready)'
                }
            }
        }

        'send' {
            if (-not $Text) {
                throw '-Text is required for send action'
            }
            switch ($Agent) {
                'codex'  { $detail = Invoke-SendCodex  -SessionName $Session -Prompt $Text }
                'claude' { $detail = Invoke-SendClaude -SessionName $Session -Prompt $Text -OneShotMode:$OneShot }
                'gemini' { $detail = Invoke-SendGemini -SessionName $Session -Prompt $Text -OneShotMode:$OneShot }
            }
        }

        'exit' {
            switch ($Agent) {
                'codex'  { $detail = Invoke-ExitCodex  -SessionName $Session -TimeoutSec $Timeout }
                'claude' { $detail = Invoke-ExitClaude -SessionName $Session -TimeoutSec $Timeout }
                'gemini' { $detail = Invoke-ExitGemini -SessionName $Session }
            }
        }
    }
} catch {
    $status = 'error'
    $detail = $_.Exception.Message
}

$result = New-AgentResult -Status $status -AgentName $Agent -ActionName $Action -Detail $detail
Write-Output $result
