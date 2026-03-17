param(
    [Parameter(Mandatory = $true)]
    [string]$SessionName,

    [Parameter(Mandatory = $true, ParameterSetName = 'prompt')]
    [string]$Prompt,

    [Parameter(Mandatory = $true, ParameterSetName = 'prompt_file')]
    [string]$PromptFile,

    [string]$WorkingDirectory = (Get-Location).Path,

    [ValidateSet('read-only', 'workspace-write', 'danger-full-access')]
    [string]$Sandbox = 'workspace-write',

    [string]$Model = '',

    [switch]$SkipGitRepoCheck,

    [int]$TimeoutSec = 600,

    [int]$TailLines = 160,

    [int]$PollMs = 800,

    [string]$JobsRoot = '',

    [switch]$WaitForPrompt,

    [switch]$NoWaitForPrompt,

    [switch]$PassThru,

    [switch]$Cleanup
)

$ErrorActionPreference = 'Stop'

function Invoke-DispatchControl {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('PING', 'STATE', 'TAIL', 'INPUT', 'LIST_TABS', 'NEW_TAB', 'CLOSE_TAB', 'SWITCH_TAB', 'FOCUS')]
        [string]$Type,

        [string]$Text = '',

        [int]$Lines = 20,

        [int]$TabIndex = -1
    )

    $sendScript = Join-Path $PSScriptRoot 'winui3-control-send.ps1'
    $controlArgs = @(
        '-SessionName', $SessionName,
        '-Type', $Type
    )

    if ($Type -eq 'INPUT') {
        $inputText = if ($Text.EndsWith("`r") -or $Text.EndsWith("`n")) {
            $Text
        } else {
            $Text + "`r"
        }
        $controlArgs += @('-Text', $inputText, '-From', 'codex-dispatch')
    } elseif ($Type -eq 'TAIL') {
        $controlArgs += @('-Lines', $Lines)
    } elseif ($Type -eq 'STATE' -and $TabIndex -ge 0) {
        $controlArgs += @('-TabIndex', $TabIndex)
    } elseif (($Type -eq 'SWITCH_TAB' -or $Type -eq 'CLOSE_TAB') -and $TabIndex -ge 0) {
        $controlArgs += @('-TabIndex', $TabIndex)
    }

    $output = & pwsh -NoLogo -NoProfile -File $sendScript @controlArgs 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "control-plane $Type failed for session '$SessionName'"
    }

    return $output
}

function Parse-DispatchState {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Text
    )

    $normalized = if ($Text -is [System.Array]) {
        ($Text -join "`n")
    } else {
        [string]$Text
    }

    $line = (($normalized -replace "`r", '') -split "`n" | Where-Object { $_ } | Select-Object -First 1)
    if (-not $line) {
        throw 'STATE reply was empty'
    }

    $parts = $line -split '\|'
    if ($parts.Length -lt 5 -or $parts[0] -ne 'STATE') {
        throw "unexpected STATE reply: $line"
    }

    $state = [ordered]@{
        Session = $parts[1]
        Pid = [int]$parts[2]
        Hwnd = $parts[3]
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
                'prompt' { $state.Prompt = $Matches.v }
                'selection' { $state.Selection = $Matches.v }
                'pwd' { $state.Pwd = $Matches.v }
                'tab_count' { $state.TabCount = [int]$Matches.v }
                'active_tab' { $state.ActiveTab = [int]$Matches.v }
            }
        }
    }

    return [pscustomobject]$state
}

function Get-DispatchState {
    return (Parse-DispatchState -Text (Invoke-DispatchControl -Type 'STATE'))
}

function Wait-DispatchPrompt {
    param(
        [int]$TimeoutMs = 20000
    )

    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    do {
        try {
            $stateText = Invoke-DispatchControl -Type 'STATE'
            $normalized = if ($stateText -is [System.Array]) {
                ($stateText -join "`n")
            } else {
                [string]$stateText
            }
            if ($normalized -match '(^|\|)prompt=1($|\|)') {
                return (Parse-DispatchState -Text $normalized)
            }
        } catch {}
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)

    throw "session '$SessionName' did not reach a shell prompt within ${TimeoutMs}ms"
}

function Wait-DispatchTailMarker {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Marker,

        [int]$TimeoutMs = 15000
    )

    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    do {
        try {
            $tail = Invoke-DispatchControl -Type 'TAIL' -Lines $TailLines
            if ($tail -and $tail.Contains($Marker)) {
                return $tail
            }
        } catch {}
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)

    return ''
}

function Quote-DispatchArg {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    return '"' + $Value.Replace('"', '""') + '"'
}

function Read-DispatchStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

if (-not $JobsRoot) {
    $JobsRoot = Join-Path $env:LOCALAPPDATA 'ghostty\control-plane\codex-jobs'
}

if ($WaitForPrompt -and $NoWaitForPrompt) {
    throw 'Use either -WaitForPrompt or -NoWaitForPrompt, not both.'
}

$jobId = 'job-' + (Get-Date -Format 'yyyyMMddHHmmss') + "-$PID-" + (Get-Random -Minimum 1000 -Maximum 9999)
$jobDir = Join-Path $JobsRoot $jobId
$jobPromptFile = Join-Path $jobDir 'prompt.txt'
$jobResultFile = Join-Path $jobDir 'result.txt'
$jobStatusFile = Join-Path $jobDir 'status.json'
$runnerScript = Join-Path $PSScriptRoot 'codex-worker-runner.ps1'

New-Item -ItemType Directory -Force -Path $jobDir | Out-Null
if ($PSCmdlet.ParameterSetName -eq 'prompt') {
    $Prompt | Set-Content -LiteralPath $jobPromptFile
} else {
    Copy-Item -LiteralPath $PromptFile -Destination $jobPromptFile -Force
}

if (-not (Test-Path -LiteralPath $WorkingDirectory)) {
    throw "Working directory not found: $WorkingDirectory"
}

if ($WaitForPrompt) {
    Wait-DispatchPrompt | Out-Null
}

$remoteArgs = @(
    'powershell',
    '-NoLogo',
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', (Quote-DispatchArg -Value $runnerScript),
    '-JobId', (Quote-DispatchArg -Value $jobId),
    '-PromptFile', (Quote-DispatchArg -Value $jobPromptFile),
    '-ResultFile', (Quote-DispatchArg -Value $jobResultFile),
    '-StatusFile', (Quote-DispatchArg -Value $jobStatusFile),
    '-WorkingDirectory', (Quote-DispatchArg -Value $WorkingDirectory),
    '-Sandbox', (Quote-DispatchArg -Value $Sandbox)
)

if ($Model) {
    $remoteArgs += @('-Model', (Quote-DispatchArg -Value $Model))
}
if ($SkipGitRepoCheck) {
    $remoteArgs += '-SkipGitRepoCheck'
}

$remoteCommand = ($remoteArgs -join ' ')
Invoke-DispatchControl -Type 'INPUT' -Text $remoteCommand | Out-Null

$beginMarker = "__CODEX_JOB_BEGIN__|$jobId"
$beginTail = Wait-DispatchTailMarker -Marker $beginMarker -TimeoutMs 20000

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$status = $null
$finalTail = ''
do {
    if (Test-Path -LiteralPath $jobStatusFile) {
        try {
            $status = Read-DispatchStatus -Path $jobStatusFile
            break
        } catch {}
    }

    Start-Sleep -Milliseconds $PollMs
} while ((Get-Date) -lt $deadline)

if (-not $status) {
    throw "job '$jobId' did not finish within ${TimeoutSec}s"
}

try {
    $finalTail = Invoke-DispatchControl -Type 'TAIL' -Lines $TailLines
} catch {
    $finalTail = ''
}

$resultText = ''
if (Test-Path -LiteralPath $jobResultFile) {
    $resultText = Get-Content -LiteralPath $jobResultFile -Raw
}

$result = [pscustomobject]@{
    JobId = $jobId
    Session = $SessionName
    WorkingDirectory = $WorkingDirectory
    Sandbox = $Sandbox
    Model = $Model
    PromptFile = $jobPromptFile
    ResultFile = $jobResultFile
    StatusFile = $jobStatusFile
    BeginTail = $beginTail
    FinalTail = $finalTail
    ExitCode = [int]$status.exit_code
    Ok = [bool]$status.ok
    Result = $resultText
    Error = [string]$status.error
}

if ($Cleanup) {
    Remove-Item -LiteralPath $jobDir -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not $result.Ok) {
    $message = "job '$jobId' failed with exit code $($result.ExitCode)"
    if ($result.Error) {
        $message += ": $($result.Error)"
    }
    throw $message
}

if ($PassThru) {
    $result
} else {
    Write-Output $result.Result
}
