param(
    [Parameter(Mandatory = $true)]
    [string]$SessionName,

    [ValidateSet('PING', 'MSG', 'STATE', 'TAIL', 'INPUT', 'RAW_INPUT', 'LIST_TABS', 'NEW_TAB', 'CLOSE_TAB', 'SWITCH_TAB', 'FOCUS')]
    [string]$Type = 'PING',

    [string]$From = 'owner',

    [string]$Text = '',

    [int]$Lines = 20,

    [int]$TabIndex = -1
)

# ============================================================================
# MINGW / Git Bash path expansion issue
# ============================================================================
# When calling this script from Git Bash (MINGW), arguments starting with "/"
# get expanded to Windows paths (e.g., "/approve" becomes
# "C:/Program Files/Git/approve"). Callers from bash must either:
#   1. Set MSYS_NO_PATHCONV=1 environment variable
#   2. Use "pwsh.exe -Command" instead of "-File" with bash
#   3. Call from PowerShell directly (no issue)
# ============================================================================

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\control-plane-session-lib.ps1"

$root = Join-Path $env:LOCALAPPDATA 'ghostty\control-plane\winui3\sessions'
if (-not (Test-Path $root)) {
    throw "Session registry not found: $root"
}

$sessionEntry = Find-ControlPlaneSessionEntry -Root $root -SessionName $SessionName
if (-not $sessionEntry) {
    throw "Session not found: $SessionName"
}

$message = if ($Type -eq 'PING') {
    'PING'
} elseif ($Type -eq 'STATE') {
    if ($TabIndex -ge 0) { "STATE|$TabIndex" } else { 'STATE' }
} elseif ($Type -eq 'TAIL') {
    "TAIL|$Lines"
} elseif ($Type -eq 'INPUT') {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $encoded = [Convert]::ToBase64String($bytes)
    "INPUT|$From|$encoded"
} elseif ($Type -eq 'RAW_INPUT') {
    # Bypass paste encoder - writes directly to PTY stdin as keyboard input
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $encoded = [Convert]::ToBase64String($bytes)
    "RAW_INPUT|$From|$encoded"
} elseif ($Type -eq 'LIST_TABS') {
    'LIST_TABS'
} elseif ($Type -eq 'NEW_TAB') {
    'NEW_TAB'
} elseif ($Type -eq 'CLOSE_TAB') {
    if ($TabIndex -ge 0) { "CLOSE_TAB|$TabIndex" } else { 'CLOSE_TAB' }
} elseif ($Type -eq 'SWITCH_TAB') {
    if ($TabIndex -ge 0) { "SWITCH_TAB|$TabIndex" } else { throw '-TabIndex is required for SWITCH_TAB' }
} elseif ($Type -eq 'FOCUS') {
    'FOCUS'
} else {
    "MSG|$From|$Text"
}

$client = [System.IO.Pipes.NamedPipeClientStream]::new('.', $sessionEntry.PipeName, [System.IO.Pipes.PipeDirection]::InOut)
try {
    $client.Connect(3000)
    $writer = [System.IO.StreamWriter]::new($client)
    $writer.AutoFlush = $true
    $reader = [System.IO.StreamReader]::new($client)
    try {
        $writer.WriteLine($message)
        $reply = $reader.ReadToEnd()
        if ($null -ne $reply) {
            Write-Output $reply
        }
    } finally {
        try { $reader.Dispose() } catch {}
        try { $writer.Dispose() } catch {}
    }
} finally {
    try { $client.Dispose() } catch {}
}
