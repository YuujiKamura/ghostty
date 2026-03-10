param()

$ErrorActionPreference = 'Stop'

$root = Join-Path $env:LOCALAPPDATA 'ghostty\control-plane\win32\sessions'
if (-not (Test-Path $root)) {
    Write-Host 'No Win32 control-plane sessions found.'
    exit 0
}

$sessions = foreach ($file in Get-ChildItem -LiteralPath $root -Filter '*.session' -File | Sort-Object LastWriteTimeUtc -Descending) {
    $map = @{}
    foreach ($line in Get-Content -LiteralPath $file.FullName) {
        if ($line -match '^(?<k>[^=]+)=(?<v>.*)$') {
            $map[$Matches.k] = $Matches.v
        }
    }
    [pscustomobject]@{
        Session = $map.session_name
        Pid = $map.pid
        Hwnd = $map.hwnd
        Pipe = $map.pipe_name
        Title = ''
        Prompt = ''
        Selection = ''
        Pwd = ''
        Log = $map.log_file
        File = $file.FullName
    }
}

if (-not $sessions) {
    Write-Host 'No Win32 control-plane sessions found.'
    exit 0
}

foreach ($session in $sessions) {
    try {
        $state = & "$PSScriptRoot\win32-control-send.ps1" -SessionName $session.Session -Type STATE 2>$null
        $parts = ($state -replace "`r","" -replace "`n","") -split '\|'
        if ($parts.Length -ge 5 -and $parts[0] -eq 'STATE') {
            $session.Title = $parts[4]
            for ($i = 5; $i -lt $parts.Length; $i++) {
                if ($parts[$i] -match '^(?<k>[^=]+)=(?<v>.*)$') {
                    switch ($Matches.k) {
                        'prompt' { $session.Prompt = $Matches.v }
                        'selection' { $session.Selection = $Matches.v }
                        'pwd' { $session.Pwd = $Matches.v }
                    }
                }
            }
        }
    } catch {}
}

$sessions | Format-Table Session,Pid,Hwnd,Prompt,Selection,Pwd,Title,Pipe,Log -AutoSize
