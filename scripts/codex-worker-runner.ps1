param(
    [Parameter(Mandatory = $true)]
    [string]$JobId,

    [Parameter(Mandatory = $true)]
    [string]$PromptFile,

    [Parameter(Mandatory = $true)]
    [string]$ResultFile,

    [Parameter(Mandatory = $true)]
    [string]$StatusFile,

    [Parameter(Mandatory = $true)]
    [string]$WorkingDirectory,

    [ValidateSet('read-only', 'workspace-write', 'danger-full-access')]
    [string]$Sandbox = 'workspace-write',

    [string]$Model = '',

    [switch]$SkipGitRepoCheck
)

$ErrorActionPreference = 'Stop'

function Write-WorkerMarker {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Phase,

        [string]$Data = ''
    )

    if ($Data) {
        Write-Host "__CODEX_JOB_${Phase}__|$JobId|$Data"
        return
    }

    Write-Host "__CODEX_JOB_${Phase}__|$JobId"
}

function Write-WorkerStatus {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Status
    )

    $parent = Split-Path -Parent $StatusFile
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    ($Status | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $StatusFile
}

$status = [ordered]@{
    job_id = $JobId
    prompt_file = $PromptFile
    result_file = $ResultFile
    status_file = $StatusFile
    working_directory = $WorkingDirectory
    sandbox = $Sandbox
    model = $Model
    started_at = (Get-Date).ToString('o')
    finished_at = $null
    ok = $false
    exit_code = $null
    result_exists = $false
    result_bytes = 0
    error = ''
}

try {
    if (-not (Test-Path -LiteralPath $PromptFile)) {
        throw "Prompt file not found: $PromptFile"
    }
    if (-not (Test-Path -LiteralPath $WorkingDirectory)) {
        throw "Working directory not found: $WorkingDirectory"
    }

    foreach ($path in @($ResultFile, $StatusFile)) {
        $parent = Split-Path -Parent $path
        if ($parent) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
    }

    Write-WorkerMarker -Phase 'BEGIN' -Data "cwd=$WorkingDirectory"

    $promptText = Get-Content -LiteralPath $PromptFile -Raw
    $codexArgs = @(
        'exec',
        '-C', $WorkingDirectory,
        '-s', $Sandbox,
        '--color', 'never',
        '--output-last-message', $ResultFile
    )

    if ($SkipGitRepoCheck) {
        $codexArgs += '--skip-git-repo-check'
    }
    if ($Model) {
        $codexArgs += @('-m', $Model)
    }
    $codexArgs += '-'

    $promptText | & codex @codexArgs
    $status.exit_code = $LASTEXITCODE
    $status.ok = ($status.exit_code -eq 0)
} catch {
    $status.exit_code = 1
    $status.ok = $false
    $status.error = ($_ | Out-String).Trim()
}

$status.finished_at = (Get-Date).ToString('o')
if (Test-Path -LiteralPath $ResultFile) {
    $item = Get-Item -LiteralPath $ResultFile
    $status.result_exists = $true
    $status.result_bytes = $item.Length
}

Write-WorkerStatus -Status $status
Write-WorkerMarker -Phase 'END' -Data "exit=$($status.exit_code)|status=$StatusFile"
exit [int]$status.exit_code
