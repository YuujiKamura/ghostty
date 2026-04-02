param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('start', 'send', 'status', 'stop')]
    [string]$Action,

    [string]$Session = 'wt-codex-tui',

    [string]$Text = '',

    [ValidateSet('powershell', 'gitbash')]
    [string]$Shell = 'powershell',

    [string]$Model = '',

    [switch]$FullAuto,

    [int]$Timeout = 30
)

$ErrorActionPreference = 'Stop'

$workerScript = Join-Path $PSScriptRoot 'winui3-ai-worker.ps1'

& pwsh -NoLogo -NoProfile -File $workerScript `
    -Action $Action `
    -Agent codex `
    -Session $Session `
    -Text $Text `
    -Shell $Shell `
    -Model $Model `
    -FullAuto:$FullAuto `
    -Timeout $Timeout

exit $LASTEXITCODE
