param(
    [Parameter(Mandatory = $true)]
    [string]$WorkerSession,

    [string[]]$PartnerSession = @(),

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

    [string]$SharePrefix = 'codex',

    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

$dispatchScript = Join-Path $PSScriptRoot 'winui3-codex-dispatch.ps1'
$sendScript = Join-Path $PSScriptRoot 'winui3-pair-send.ps1'

. "$PSScriptRoot\pair-bus-lib.ps1"

$PartnerSession = Expand-PairBusSessionNames -SessionName $PartnerSession

function Send-PairProgress {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    if ($PartnerSession.Count -eq 0) {
        return
    }

    & pwsh -NoLogo -NoProfile -File $sendScript `
        -ToSession $PartnerSession `
        -FromSession $WorkerSession `
        -Kind $Kind `
        -Text $Text 2>$null | Out-Null
}

$promptLabel = if ($PSCmdlet.ParameterSetName -eq 'prompt') {
    $Prompt
} else {
    Split-Path -Leaf $PromptFile
}
if ($promptLabel.Length -gt 80) {
    $promptLabel = $promptLabel.Substring(0, 80) + '...'
}

Send-PairProgress -Kind 'queued' -Text "$SharePrefix queued in $WorkerSession ($promptLabel)"

$dispatchParams = @{
    SessionName = $WorkerSession
    WorkingDirectory = $WorkingDirectory
    Sandbox = $Sandbox
    TimeoutSec = $TimeoutSec
    TailLines = $TailLines
    PollMs = $PollMs
    PassThru = $true
}
if ($PSCmdlet.ParameterSetName -eq 'prompt') {
    $dispatchParams.Prompt = $Prompt
} else {
    $dispatchParams.PromptFile = $PromptFile
}
if ($Model) {
    $dispatchParams.Model = $Model
}
if ($SkipGitRepoCheck) {
    $dispatchParams.SkipGitRepoCheck = $true
}
if ($JobsRoot) {
    $dispatchParams.JobsRoot = $JobsRoot
}

try {
    $result = & $dispatchScript @dispatchParams
    $summary = if ($result.Result) {
        ([string]$result.Result).Trim()
    } else {
        ''
    }
    if ($summary.Length -gt 80) {
        $summary = $summary.Substring(0, 80) + '...'
    }
    Send-PairProgress -Kind 'done' -Text "$SharePrefix done in $WorkerSession (exit=$($result.ExitCode)) $summary"

    if ($PassThru) {
        $result
    } else {
        Write-Output $result.Result
    }
} catch {
    Send-PairProgress -Kind 'fail' -Text "$SharePrefix failed in ${WorkerSession}: $($_.Exception.Message)"
    throw
}
