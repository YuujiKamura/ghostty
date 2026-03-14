param(
    [Parameter(Mandatory = $true)]
    [string]$SessionName,

    [ValidateSet('PING', 'MSG', 'STATE', 'TAIL', 'INPUT')]
    [string]$Type = 'PING',

    [string]$From = 'owner',

    [string]$Text = '',

    [int]$Lines = 20
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\control-plane-session-lib.ps1"

$root = Join-Path $env:LOCALAPPDATA 'ghostty\control-plane\win32\sessions'
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
    'STATE'
} elseif ($Type -eq 'TAIL') {
    "TAIL|$Lines"
} elseif ($Type -eq 'INPUT') {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $encoded = [Convert]::ToBase64String($bytes)
    "INPUT|$From|$encoded"
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
