param()

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\control-plane-session-lib.ps1"

$root = Join-Path $env:LOCALAPPDATA 'ghostty\control-plane\win32\sessions'
$sessions = foreach ($entry in Get-ControlPlaneSessionEntries -Root $root) {
    [pscustomobject]@{
        Session = $entry.Session
        Pid = $entry.Pid
        Hwnd = $entry.Hwnd
        Pipe = $entry.PipeName
        Title = ''
        Prompt = ''
        Selection = ''
        Pwd = ''
        Log = $entry.Log
        File = $entry.File
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
