param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('start', 'send', 'status', 'stop')]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [ValidateSet('codex', 'claude', 'gemini')]
    [string]$Agent,

    [string]$Session = '',

    [string]$Text = '',

    [ValidateSet('powershell', 'gitbash')]
    [string]$Shell = 'powershell',

    [string]$Model = '',

    [switch]$FullAuto,

    [switch]$OneShot,

    [int]$Timeout = 30
)

$ErrorActionPreference = 'Stop'

$agentSendScript = Join-Path $PSScriptRoot 'winui3-agent-send.ps1'
$controlSendScript = Join-Path $PSScriptRoot 'winui3-control-send.ps1'
$sessionsDir = Join-Path $env:LOCALAPPDATA 'ghostty\control-plane\winui3\sessions'
$logsDir = Join-Path $env:LOCALAPPDATA 'ghostty\control-plane\winui3\logs'

if (-not $Session) {
    $Session = "wt-$Agent-$Shell"
}

function Resolve-GitBashPath {
    $candidates = @(
        'C:\Program Files\Git\bin\bash.exe',
        'C:\Program Files\Git\usr\bin\bash.exe'
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $cmd = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    throw 'git bash not found'
}

function Get-LaunchCommand {
    param(
        [string]$AgentName,
        [string]$ModelName,
        [switch]$FullAutoMode
    )

    switch ($AgentName) {
        'codex' {
            $parts = @('codex', '--no-alt-screen', '--dangerously-bypass-approvals-and-sandbox')
            if ($FullAutoMode) {
                $parts += '--full-auto'
            }
            if ($ModelName) {
                $parts += @('-m', $ModelName)
            }
            return (($parts -join ' ') + "`r")
        }
        'claude' {
            return "claude`r"
        }
        'gemini' {
            return ''
        }
    }
}

function Get-WorkerSessionFile {
    param([string]$SessionName)

    if (-not (Test-Path $sessionsDir)) {
        return $null
    }

    Get-ChildItem $sessionsDir -Filter "$SessionName-*.session" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Get-WorkerPid {
    param([System.IO.FileInfo]$SessionFile)

    if ($null -eq $SessionFile) {
        return $null
    }

    [int](([IO.Path]::GetFileNameWithoutExtension($SessionFile.Name) -split '-')[-1])
}

function Get-WorkerProcess {
    param([int]$ProcessId)

    if (-not $ProcessId) {
        return $null
    }

    Get-Process WindowsTerminal -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -eq $ProcessId } |
        Select-Object -First 1
}

function Get-DevWorkerProcesses {
    Get-Process WindowsTerminal -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -like 'C:\Users\yuuji\WindowsTerminal\src\cascadia\CascadiaPackage\bin\x64\Debug\*' }
}

function Stop-DevWorkerProcesses {
    $procs = Get-DevWorkerProcesses
    if ($procs) {
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
}

function Wait-ForSessionFile {
    param(
        [string]$SessionName,
        [int]$TimeoutSec
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $file = Get-WorkerSessionFile -SessionName $SessionName
        if ($file) {
            return $file
        }
        Start-Sleep -Milliseconds 500
    }

    throw "session file not created: $SessionName"
}

function Wait-ForPing {
    param(
        [string]$SessionName,
        [int]$TimeoutSec
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $reply = & pwsh -NoLogo -NoProfile -File $controlSendScript -SessionName $SessionName -Type PING 2>$null
            if ($LASTEXITCODE -eq 0 -and $reply) {
                return [string]$reply
            }
        } catch {
        }
        Start-Sleep -Seconds 1
    }

    throw "control-plane ping timed out: $SessionName"
}

function Start-Worker {
    param(
        [string]$SessionName,
        [string]$AgentName,
        [string]$ShellName,
        [string]$ModelName,
        [switch]$FullAutoMode,
        [int]$TimeoutSec
    )

    $existing = Get-WorkerSessionFile -SessionName $SessionName
    if ($existing) {
        $existingPid = Get-WorkerPid -SessionFile $existing
        $existingProc = Get-WorkerProcess -ProcessId $existingPid
        if ($existingProc) {
            $ping = Wait-ForPing -SessionName $SessionName -TimeoutSec 10
            return [pscustomobject]@{
                Agent = $AgentName
                Shell = $ShellName
                SessionFile = $existing.FullName
                Pid = $existingPid
                Ping = $ping.Trim()
                Reused = $true
            }
        }

        Remove-Item $existing.FullName -Force -ErrorAction SilentlyContinue
    }

    Remove-Item (Join-Path $sessionsDir "$SessionName-*.session") -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $logsDir "$SessionName-*.log") -Force -ErrorAction SilentlyContinue
    Stop-DevWorkerProcesses

    $env:GHOSTTY_CONTROL_PLANE = '1'
    $env:GHOSTTY_SESSION_NAME = $SessionName
    Start-Process wtd.exe | Out-Null

    $sessionFile = Wait-ForSessionFile -SessionName $SessionName -TimeoutSec $TimeoutSec
    $workerPid = Get-WorkerPid -SessionFile $sessionFile
    $ping = Wait-ForPing -SessionName $SessionName -TimeoutSec $TimeoutSec

    if ($ShellName -eq 'gitbash') {
        $bashPath = Resolve-GitBashPath
        $bashCommand = "& '$bashPath' -li`r"
        & pwsh -NoLogo -NoProfile -File $controlSendScript -SessionName $SessionName -Type INPUT -From 'worker-start' -Text $bashCommand 2>$null | Out-Null
        Start-Sleep -Seconds 2
    }

    $launchCommand = Get-LaunchCommand -AgentName $AgentName -ModelName $ModelName -FullAutoMode:$FullAutoMode
    if ($launchCommand) {
        & pwsh -NoLogo -NoProfile -File $controlSendScript -SessionName $SessionName -Type INPUT -From 'worker-start' -Text $launchCommand 2>$null | Out-Null
    }

    [pscustomobject]@{
        Agent = $AgentName
        Shell = $ShellName
        SessionFile = $sessionFile.FullName
        Pid = $workerPid
        Ping = $ping.Trim()
        Reused = $false
    }
}

function Get-Status {
    param(
        [string]$SessionName,
        [string]$AgentName,
        [string]$ShellName
    )

    $sessionFile = Get-WorkerSessionFile -SessionName $SessionName
    if (-not $sessionFile) {
        return [pscustomobject]@{
            Agent = $AgentName
            Shell = $ShellName
            Session = $SessionName
            Running = $false
        }
    }

    $workerPid = Get-WorkerPid -SessionFile $sessionFile
    $proc = Get-WorkerProcess -ProcessId $workerPid
    $logPath = Join-Path $logsDir ($sessionFile.BaseName + '.log')

    $ping = ''
    if ($proc) {
        try {
            $ping = [string](& pwsh -NoLogo -NoProfile -File $controlSendScript -SessionName $SessionName -Type PING 2>$null)
        } catch {
        }
    }

    [pscustomobject]@{
        Agent = $AgentName
        Shell = $ShellName
        Session = $SessionName
        Running = ($null -ne $proc)
        Pid = $workerPid
        SessionFile = $sessionFile.FullName
        LogFile = $logPath
        Ping = $ping.Trim()
    }
}

switch ($Action) {
    'start' {
        Start-Worker -SessionName $Session -AgentName $Agent -ShellName $Shell -ModelName $Model -FullAutoMode:$FullAuto -TimeoutSec $Timeout | Format-List
    }
    'send' {
        if (-not $Text) {
            throw '-Text is required for send'
        }

        $null = Start-Worker -SessionName $Session -AgentName $Agent -ShellName $Shell -ModelName $Model -FullAutoMode:$FullAuto -TimeoutSec $Timeout
        $oneShotMode = $OneShot
        if ($Agent -eq 'gemini') {
            $oneShotMode = $true
        }
        & pwsh -NoLogo -NoProfile -File $agentSendScript -Agent $Agent -Action send -Session $Session -Text $Text -OneShot:$oneShotMode
    }
    'status' {
        Get-Status -SessionName $Session -AgentName $Agent -ShellName $Shell | Format-List
    }
    'stop' {
        & pwsh -NoLogo -NoProfile -File $agentSendScript -Agent $Agent -Action exit -Session $Session -Timeout $Timeout
    }
}
