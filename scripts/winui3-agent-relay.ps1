param(
    [Parameter(Mandatory = $true)]
    [string]$ToSession,

    [Parameter(Mandatory = $true, ParameterSetName = 'text')]
    [string]$Text,

    [Parameter(Mandatory = $true, ParameterSetName = 'file')]
    [string]$TextFile,

    [string]$FromSession = 'controller',

    [string[]]$ShareToSession = @(),

    [string]$Kind = 'relay',

    [switch]$NoSubmit,

    [switch]$NoControlLog,

    [int]$ChunkChars = 0,

    [int]$ChunkDelayMs = 40,

    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\pair-bus-lib.ps1"

$controlSendScript = Join-Path $PSScriptRoot 'winui3-control-send.ps1'
$pairSendScript = Join-Path $PSScriptRoot 'winui3-pair-send.ps1'

$ShareToSession = Expand-PairBusSessionNames -SessionName $ShareToSession

function Get-RelayPayload {
    if ($PSCmdlet.ParameterSetName -eq 'file') {
        if (-not (Test-Path -LiteralPath $TextFile)) {
            throw "Text file not found: $TextFile"
        }

        return (Get-Content -LiteralPath $TextFile -Raw)
    }

    return $Text
}

function Get-RelayPreview {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $preview = $Value.Replace("`r", '').Replace("`n", ' <NL> ').Trim()
    if ($preview.Length -gt 120) {
        return $preview.Substring(0, 120) + '...'
    }

    return $preview
}

function Send-RelayShare {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    if ($ShareToSession.Count -eq 0) {
        return
    }

    & pwsh -NoLogo -NoProfile -File $pairSendScript `
        -ToSession $ShareToSession `
        -FromSession $FromSession `
        -Kind $Kind `
        -Text $Text `
        -NoControlLog:$NoControlLog 2>$null | Out-Null
}

function Send-RelayChunk {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Chunk
    )

    & pwsh -NoLogo -NoProfile -File $controlSendScript `
        -SessionName $ToSession `
        -Type INPUT `
        -From $FromSession `
        -Text $Chunk 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "relay INPUT failed for session '$ToSession'"
    }
}

$payload = [string](Get-RelayPayload)
if (-not $NoSubmit -and -not $payload.EndsWith("`r") -and -not $payload.EndsWith("`n")) {
    $payload += "`r"
}

$preview = Get-RelayPreview -Value $payload
Send-RelayShare -Text "relay queued from $FromSession to ${ToSession}: $preview"

$chunkCount = 0
if ($ChunkChars -gt 0 -and $payload.Length -gt $ChunkChars) {
    for ($offset = 0; $offset -lt $payload.Length; $offset += $ChunkChars) {
        $length = [Math]::Min($ChunkChars, $payload.Length - $offset)
        $chunk = $payload.Substring($offset, $length)
        Send-RelayChunk -Chunk $chunk
        $chunkCount += 1
        if ($offset + $length -lt $payload.Length -and $ChunkDelayMs -gt 0) {
            Start-Sleep -Milliseconds $ChunkDelayMs
        }
    }
} else {
    Send-RelayChunk -Chunk $payload
    $chunkCount = 1
}

$result = [pscustomobject]@{
    ToSession = $ToSession
    FromSession = $FromSession
    Kind = $Kind
    Submitted = (-not $NoSubmit)
    Characters = $payload.Length
    Chunks = $chunkCount
    Preview = $preview
}

Send-RelayShare -Text "relay delivered from $FromSession to ${ToSession} ($chunkCount chunk): $preview"

if ($PassThru) {
    $result
} else {
    Write-Output $result.Preview
}
