param(
    [string[]]$SessionName = @(),

    [int]$Latest = 15,

    [string]$Root = '',

    [switch]$Watch,

    [int]$IntervalSec = 2,

    [switch]$ShowTail,

    [int]$TailLines = 10
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\control-plane-session-lib.ps1"
. "$PSScriptRoot\pair-bus-lib.ps1"

$SessionName = Expand-PairBusSessionNames -SessionName $SessionName

function Parse-PairMonitorState {
    param([Parameter(Mandatory = $true)][object]$Text)

    $normalized = if ($Text -is [System.Array]) {
        ($Text -join "`n")
    } else {
        [string]$Text
    }
    $line = (($normalized -replace "`r", '') -split "`n" | Where-Object { $_ } | Select-Object -First 1)
    if (-not $line) {
        throw 'empty STATE'
    }

    $parts = $line -split '\|'
    if ($parts.Length -lt 5 -or $parts[0] -ne 'STATE') {
        throw "unexpected STATE: $line"
    }

    $row = [ordered]@{
        Session = $parts[1]
        Pid = [int]$parts[2]
        Title = $parts[4]
        Prompt = '0'
        Selection = '0'
        Pwd = ''
        TabCount = 0
        ActiveTab = 0
    }

    for ($i = 5; $i -lt $parts.Length; $i++) {
        if ($parts[$i] -match '^(?<k>[^=]+)=(?<v>.*)$') {
            switch ($Matches.k) {
                'prompt' { $row.Prompt = $Matches.v }
                'selection' { $row.Selection = $Matches.v }
                'pwd' { $row.Pwd = $Matches.v }
                'tab_count' { $row.TabCount = [int]$Matches.v }
                'active_tab' { $row.ActiveTab = [int]$Matches.v }
            }
        }
    }

    return [pscustomobject]$row
}

function Normalize-PairMonitorTail {
    param([Parameter(Mandatory = $true)][object]$Text)

    $normalized = if ($Text -is [System.Array]) {
        ($Text -join "`n")
    } else {
        [string]$Text
    }

    $lines = ($normalized -replace "`r", '') -split "`n"
    if ($lines.Count -gt 0 -and $lines[0] -like 'TAIL|*') {
        $lines = @($lines | Select-Object -Skip 1)
    }

    return (($lines -join "`n").TrimEnd())
}

function Get-PairMonitorSessions {
    $rootSessions = Join-Path $env:LOCALAPPDATA 'ghostty\control-plane\winui3\sessions'
    $entries = Get-ControlPlaneSessionEntries -Root $rootSessions
    if ($SessionName.Count -gt 0) {
        $entries = @($entries | Where-Object { $_.Session -in $SessionName })
    }

    $sendScript = Join-Path $PSScriptRoot 'winui3-control-send.ps1'
    $rows = foreach ($entry in $entries) {
        try {
            $stateText = & pwsh -NoLogo -NoProfile -File $sendScript -SessionName $entry.Session -Type STATE 2>$null
            if ($LASTEXITCODE -ne 0) {
                continue
            }
            $row = Parse-PairMonitorState -Text $stateText
            if ($ShowTail) {
                try {
                    $tailText = & pwsh -NoLogo -NoProfile -File $sendScript -SessionName $entry.Session -Type TAIL -Lines $TailLines 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        $row | Add-Member -NotePropertyName Tail -NotePropertyValue (Normalize-PairMonitorTail -Text $tailText)
                    }
                } catch {}
            }
            $row
        } catch {}
    }

    return @($rows)
}

function Show-PairMonitor {
    $sessions = Get-PairMonitorSessions
    $messages = Get-PairBusMessages -Root $Root -Latest $Latest -SessionName $SessionName

    Write-Host '== Live Sessions =='
    if ($sessions.Count -eq 0) {
        Write-Host 'No live WinUI3 control-plane sessions.'
    } else {
        $sessions | Format-Table Session,Pid,Prompt,Selection,Pwd,TabCount,ActiveTab,Title -AutoSize
    }

    Write-Host ''
    Write-Host '== Recent Pair Messages =='
    if ($messages.Count -eq 0) {
        Write-Host 'No pair-bus messages.'
    } else {
        $messages |
            Select-Object CreatedAt,From,To,Kind,Text |
            Format-Table -AutoSize -Wrap
    }

    if ($ShowTail -and $sessions.Count -gt 0) {
        Write-Host ''
        Write-Host '== Session Tails =='
        foreach ($session in $sessions) {
            Write-Host ''
            Write-Host ('[' + $session.Session + ']')
            if ($session.PSObject.Properties.Name -contains 'Tail' -and $session.Tail) {
                Write-Host $session.Tail
            } else {
                Write-Host '(no tail)'
            }
        }
    }
}

if ($Watch) {
    while ($true) {
        Clear-Host
        Show-PairMonitor
        Start-Sleep -Seconds $IntervalSec
    }
}

Show-PairMonitor
