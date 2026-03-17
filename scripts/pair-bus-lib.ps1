function Get-PairBusRoot {
    param([string]$Root = '')

    if ([string]::IsNullOrWhiteSpace($Root)) {
        return (Join-Path $env:LOCALAPPDATA 'ghostty\control-plane\pair-bus')
    }

    return $Root
}

function Expand-PairBusSessionNames {
    param([string[]]$SessionName = @())

    $expanded = foreach ($value in $SessionName) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }

        foreach ($part in ($value -split ',')) {
            $trimmed = $part.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                $trimmed
            }
        }
    }

    return @($expanded)
}

function Get-PairBusMessagesDir {
    param([string]$Root = '')
    return (Join-Path (Get-PairBusRoot -Root $Root) 'messages')
}

function Ensure-PairBusMessagesDir {
    param([string]$Root = '')

    $messagesDir = Get-PairBusMessagesDir -Root $Root
    New-Item -ItemType Directory -Force -Path $messagesDir | Out-Null
    return $messagesDir
}

function New-PairBusMessageId {
    $stamp = Get-Date -Format 'yyyyMMddHHmmssfff'
    $rand = Get-Random -Minimum 1000 -Maximum 9999
    return "msg-$stamp-$rand"
}

function Write-PairBusMessage {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Message,

        [string]$Root = ''
    )

    $messagesDir = Ensure-PairBusMessagesDir -Root $Root
    $fileName = '{0}_{1}_{2}.json' -f $Message.created_at.Replace(':', '-'), $Message.id, $Message.to
    $path = Join-Path $messagesDir $fileName
    ($Message | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $path
    return $path
}

function Get-PairBusMessages {
    param(
        [string]$Root = '',

        [int]$Latest = 20,

        [string[]]$SessionName = @()
    )

    $messagesDir = Get-PairBusMessagesDir -Root $Root
    if (-not (Test-Path -LiteralPath $messagesDir)) {
        return @()
    }

    $files = Get-ChildItem -LiteralPath $messagesDir -Filter '*.json' -File |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First $Latest

    $messages = foreach ($file in $files) {
        try {
            $message = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            if ($SessionName.Count -gt 0) {
                if ($message.from -notin $SessionName -and $message.to -notin $SessionName) {
                    continue
                }
            }
            [pscustomobject]@{
                Id = $message.id
                CreatedAt = $message.created_at
                From = $message.from
                To = $message.to
                Kind = $message.kind
                Text = $message.text
                File = $file.FullName
            }
        } catch {}
    }

    return @($messages)
}
