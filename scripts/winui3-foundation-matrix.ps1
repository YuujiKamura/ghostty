param(
    [string]$ExePath = (Join-Path (Split-Path -Parent $PSScriptRoot) "zig-out\bin\ghostty.exe"),
    [int]$WaitSeconds = 8
)

$ErrorActionPreference = "Stop"

function Run-Case {
    param(
        [string]$Name,
        [hashtable]$Env
    )

    Write-Host "=== CASE: $Name ==="
    $proc = Start-Process -FilePath $ExePath -PassThru -WindowStyle Hidden -Environment $Env
    Start-Sleep -Seconds $WaitSeconds

    $result = [ordered]@{
        case = $Name
        pid = $proc.Id
        alive_after_wait = -not $proc.HasExited
        exit_code = if ($proc.HasExited) { $proc.ExitCode } else { $null }
    }

    if (-not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }

    [pscustomobject]$result
}

$baseEnv = @{}

$cases = @(
    @{ name = "baseline"; env = $baseEnv }
)

$rows = @()
foreach ($case in $cases) {
    if ($case.patch) {
        foreach ($k in $case.patch.Keys) {
            $case.env[$k] = $case.patch[$k]
        }
    }
    $rows += Run-Case -Name $case.name -Env $case.env
}

$rows | Format-Table -AutoSize
