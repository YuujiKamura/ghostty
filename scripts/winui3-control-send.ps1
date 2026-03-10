param(
    [Parameter(Mandatory = $true)]
    [string]$SessionName,

    [ValidateSet('PING', 'MSG', 'STATE', 'TAIL', 'INPUT')]
    [string]$Type = 'PING',

    [string]$From = 'owner',

    [string]$Text = '',

    [int]$Lines = 20,

    [int]$TabIndex = -1
)

$ErrorActionPreference = 'Stop'

$root = Join-Path $env:LOCALAPPDATA 'ghostty\control-plane\winui3\sessions'
if (-not (Test-Path $root)) {
    throw "Session registry not found: $root"
}

$sessionFile = $null
foreach ($file in Get-ChildItem -LiteralPath $root -Filter '*.session' -File) {
    $map = @{}
    foreach ($line in Get-Content -LiteralPath $file.FullName) {
        if ($line -match '^(?<k>[^=]+)=(?<v>.*)$') {
            $map[$Matches.k] = $Matches.v
        }
    }
    if ($map.session_name -eq $SessionName -or $map.safe_session_name -eq $SessionName -or $map.pipe_name -eq $SessionName) {
        $sessionFile = [pscustomobject]@{
            File = $file.FullName
            PipeName = $map.pipe_name
            Session = $map.session_name
        }
        break
    }
}

if (-not $sessionFile) {
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
} else {
    "MSG|$From|$Text"
}

$client = [System.IO.Pipes.NamedPipeClientStream]::new('.', $sessionFile.PipeName, [System.IO.Pipes.PipeDirection]::InOut)
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
