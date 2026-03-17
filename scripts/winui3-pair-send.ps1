param(
    [Parameter(Mandatory = $true)]
    [string[]]$ToSession,

    [Parameter(Mandatory = $true)]
    [string]$Text,

    [string]$FromSession = 'controller',

    [string]$Kind = 'note',

    [string]$Root = '',

    [switch]$NoControlLog
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\pair-bus-lib.ps1"

$ToSession = Expand-PairBusSessionNames -SessionName $ToSession

$sendScript = Join-Path $PSScriptRoot 'winui3-control-send.ps1'
$sent = foreach ($target in $ToSession) {
    $message = [ordered]@{
        id = New-PairBusMessageId
        created_at = (Get-Date).ToString('o')
        from = $FromSession
        to = $target
        kind = $Kind
        text = $Text
    }

    $path = Write-PairBusMessage -Message $message -Root $Root

    $logged = $false
    if (-not $NoControlLog) {
        $logText = "[PAIR][$FromSession][$Kind] $Text"
        try {
            & pwsh -NoLogo -NoProfile -File $sendScript -SessionName $target -Type MSG -From $FromSession -Text $logText 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $logged = $true
            }
        } catch {}
    }

    [pscustomobject]@{
        Id = $message.id
        CreatedAt = $message.created_at
        From = $FromSession
        To = $target
        Kind = $Kind
        Text = $Text
        File = $path
        LoggedToControlPlane = $logged
    }
}

$sent
