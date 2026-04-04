#Requires -Version 5.1
<#
.SYNOPSIS
    Regression test for D3D11 bg_cells binding path (Issue #146).

.DESCRIPTION
    This test intentionally checks for the known broken state in the current
    D3D11 path: additional buffers (bg_cells) are present but not bound.

    Current expected result (before fix): FAIL
    Expected result after fix:            PASS

    Run:
      .\test_bg_cells_binding.ps1
      .\test_bg_cells_binding.ps1 -Attach
#>

param(
    [switch]$Attach,
    [switch]$Runtime,
    [string]$EvidenceDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$script:RepoRoot    = (Resolve-Path "$PSScriptRoot\..\..").Path
$script:GhosttyExe  = Join-Path $RepoRoot "zig-out-winui3\bin\ghostty.exe"
$script:SessionDir  = Join-Path $env:LOCALAPPDATA "ghostty\control-plane\winui3\sessions"
$script:LogPath     = $null
$script:GhosttyProc = $null
$script:PipeName    = $null
$script:Launched    = $false
$script:GhosttyPid  = 0

function Log([string]$msg) { Write-Host "[bg-cells-test] $msg" }

function Send-CP([string]$cmd) {
    try {
        $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", $script:PipeName, [System.IO.Pipes.PipeDirection]::InOut)
        $pipe.Connect(3000)
        $writer = New-Object System.IO.StreamWriter($pipe)
        $reader = New-Object System.IO.StreamReader($pipe)
        $writer.AutoFlush = $true
        $writer.WriteLine($cmd)
        $response = $reader.ReadToEnd()
        $pipe.Close()
        return $response
    } catch {
        return "ERROR|$($_.Exception.Message)"
    }
}

function Parse-SessionFile([string]$Path) {
    $props = @{}
    Get-Content $Path | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            $props[$Matches[1]] = $Matches[2]
        }
    }
    return $props
}

function Get-PipeNameFromSession([string]$SessionPath) {
    $props = Parse-SessionFile $SessionPath
    if ($props.ContainsKey("pipe_path")) {
        $full = $props["pipe_path"]
        if ($full -match '\\\\\.\\pipe\\(.+)$') {
            return $Matches[1]
        }
    }
    return $null
}

function Find-Session {
    if (-not (Test-Path $script:SessionDir)) { return $false }
    $sessions = @()
    $sessions += Get-ChildItem $script:SessionDir -Filter "*.session" -ErrorAction SilentlyContinue
    $sessions += Get-ChildItem $script:SessionDir -Filter "*.json" -ErrorAction SilentlyContinue
    foreach ($s in $sessions) {
        if ($s.Extension -eq ".session") {
            $script:PipeName = Get-PipeNameFromSession $s.FullName
        } else {
            $json = Get-Content $s.FullName -Raw | ConvertFrom-Json
            $script:PipeName = $json.pipe_name
            if (-not $script:PipeName) { $script:PipeName = $json.pipeName }
        }
        if ($script:PipeName) {
            $ping = Send-CP "PING"
            if ($ping -match "PONG") { return $true }
        }
    }
    return $false
}

function Start-Ghostty {
    if ($Attach) {
        if (Find-Session) {
            Log "Attached to running ghostty (pipe: $script:PipeName)"
            if ($script:PipeName -match 'ghostty-(\d+)-(\d+)$') {
                $script:GhosttyPid = [int]$Matches[1]
            }
            return $true
        }
        Log "FAIL: -Attach specified but no running ghostty found"
        return $false
    }

    if (-not (Test-Path $script:GhosttyExe)) {
        Log "FAIL: ghostty.exe not found: $script:GhosttyExe"
        return $false
    }

    # Enable diagnostic trace for this test session.
    $env:GHOSTTY_CONTROL_PLANE = "1"
    $env:GHOSTTY_TRACE_BG_CELLS = "1"
    $env:GHOSTTY_LOG = "true"
    $script:GhosttyProc = Start-Process -FilePath $script:GhosttyExe -PassThru -ErrorAction SilentlyContinue
    if (-not $script:GhosttyProc) {
        Log "FAIL: Could not start ghostty"
        return $false
    }
    $script:GhosttyPid = $script:GhosttyProc.Id
    $script:Launched = $true
    Start-Sleep -Seconds 3

    for ($i = 0; $i -lt 12; $i++) {
        if (Find-Session) {
            Log "Ghostty started (PID=$($script:GhosttyProc.Id), pipe: $script:PipeName)"
            return $true
        }
        Start-Sleep -Seconds 1
    }
    Log "FAIL: Ghostty started but no CP session found"
    return $false
}

function Stop-Ghostty {
    if ($script:Launched -and $script:GhosttyProc -and -not $script:GhosttyProc.HasExited) {
        Stop-Process -Id $script:GhosttyProc.Id -Force -ErrorAction SilentlyContinue
        Log "Ghostty stopped"
    }
}

function Get-RecentLogLines([int]$tail = 4000) {
    if (-not $script:LogPath -or -not (Test-Path $script:LogPath)) { return @() }
    return @(Get-Content $script:LogPath -Tail $tail -ErrorAction SilentlyContinue)
}

function Resolve-LogPath {
    $candidates = @(
        (Join-Path $env:TEMP "ghostty_debug.log"),
        (Join-Path $env:LOCALAPPDATA "ghostty\ghostty.log")
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Resolve-DeskpilotExe {
    $repo = Join-Path $HOME "windows-screenshot-mcp-server"
    if (-not (Test-Path $repo)) { return $null }

    $candidates = @(
        (Join-Path $repo "deskpilot.exe"),
        (Join-Path $repo "bin\deskpilot.exe")
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }

    # Build lazily if missing.
    try {
        Push-Location $repo
        & go build -o deskpilot.exe .\cmd\deskpilot | Out-Null
        Pop-Location
    } catch {
        try { Pop-Location } catch {}
        return $null
    }
    $built = Join-Path $repo "deskpilot.exe"
    if (Test-Path $built) { return $built }
    return $null
}

function Capture-EvidenceWithDeskpilot([int]$TargetPid, [string]$OutDir) {
    $exe = Resolve-DeskpilotExe
    if (-not $exe) {
        Log "WARN: deskpilot.exe not available (windows-screenshot-mcp-server)."
        return @()
    }
    if ($TargetPid -le 0) {
        Log "WARN: valid PID is required for deskpilot capture."
        return @()
    }

    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    $methods = @("print", "capture", "bitblt", "auto")
    $saved = @()
    foreach ($m in $methods) {
        $out = Join-Path $OutDir ("ghostty-{0}.png" -f $m)
        $args = @("--pid", "$TargetPid", "--method", $m, "--output", $out, "--format", "png")
        try {
            & $exe @args 2>$null | Out-Null
            if (Test-Path $out) {
                $item = Get-Item $out
                if ($item.Length -gt 0) {
                    $saved += $out
                    Log "Evidence captured via deskpilot method=$m -> $out"
                }
            }
        } catch {
            Log "WARN: deskpilot capture failed method=${m}: $($_.Exception.Message)"
        }
    }
    return $saved
}

try {
    Log "=== D3D11 bg_cells binding regression test (Issue #146) ==="

    # Static causal gate:
    # 1) generic renderer passes bg_cells as additional buffer
    # 2) D3D11 RenderPass only binds buffers[0] and leaves extra buffers unbound
    # If both are true, bg_cells is structurally dropped in D3D11.
    $renderPassPath = Join-Path $script:RepoRoot "src\renderer\d3d11\RenderPass.zig"
    $genericPath = Join-Path $script:RepoRoot "src\renderer\generic.zig"
    if (-not (Test-Path $renderPassPath)) {
        Log "FAIL: RenderPass.zig not found: $renderPassPath"
        exit 5
    }
    if (-not (Test-Path $genericPath)) {
        Log "FAIL: generic.zig not found: $genericPath"
        exit 6
    }

    $renderSrc = Get-Content $renderPassPath -Raw
    $genericSrc = Get-Content $genericPath -Raw

    $producerPassesBgCells = $genericSrc -match '\.buffers\s*=\s*&\.\{\s*null,\s*frame\.cells_bg\.buffer\s*\}' -or
        $genericSrc -match '\.buffers\s*=\s*&\.\{\s*frame\.cells\.buffer,\s*frame\.cells_bg\.buffer\s*\}'

    $consumerHasSrvBinding = $renderSrc -match 'ctx\.vsSetShaderResources\(2,\s*s\.buffer_srvs\)' -and
        $renderSrc -match 'ctx\.psSetShaderResources\(2,\s*s\.buffer_srvs\)'
    $consumerStillDropsExtras = $renderSrc -match 'extra buffers present but no SRV binding provided'

    if ($producerPassesBgCells -and $consumerStillDropsExtras -and -not $consumerHasSrvBinding) {
        Log "FAIL: causal mismatch confirmed (generic passes bg_cells extra buffer, d3d11 RenderPass drops extras)."
        exit 1
    }

    if (-not $producerPassesBgCells) {
        Log "WARN: producer pattern not found; this test may need update to match new generic path."
    }
    if (-not $consumerHasSrvBinding) {
        Log "WARN: consumer SRV binding pattern not found; RenderPass may still be incomplete."
    }

    if (-not $Runtime) {
        Log "PASS: static causal mismatch not detected."
        exit 0
    }

    if (-not (Start-Ghostty)) {
        exit 2
    }
    $script:LogPath = Resolve-LogPath

    # Trigger at least one render/update cycle.
    $marker = "BG_BIND_TEST_$(Get-Random -Maximum 99999)"
    $cmd = "echo $marker"
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$cmd`r"))
    $resp = Send-CP ("INPUT|bgtest|{0}" -f $b64)
    Log "CP INPUT response: $resp"
    Start-Sleep -Seconds 2
    $traceDiag = Send-CP "BGTRACE_STATE"
    Log "CP BGTRACE_STATE response: $traceDiag"

    # Capture visual evidence using windows-screenshot-mcp-server (deskpilot).
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    if (-not $EvidenceDir) {
        $EvidenceDir = Join-Path $script:RepoRoot ("tests\self_diagnosis\artifacts\bg-cells\{0}" -f $stamp)
    }
    $captures = @(Capture-EvidenceWithDeskpilot -TargetPid $script:GhosttyPid -OutDir $EvidenceDir)
    if (@($captures).Count -eq 0) {
        Log "WARN: no deskpilot captures produced. EvidenceDir=$EvidenceDir"
    }

    $bindCounter = 0
    $traceEnabled = $false
    if ($traceDiag -match 'OK\|enabled=(\d+)\|bind_counter=(\d+)\|sentinel=(\d+)') {
        $traceEnabled = ([int]$Matches[1]) -eq 1
        $bindCounter = [int]$Matches[2]
    }

    if (-not $traceEnabled -or $bindCounter -le 0) {
        $lines = @(Get-RecentLogLines)
        if (@($lines).Count -eq 0) {
            Log "FAIL: trace not active (cp_diag='$traceDiag', log_path=$script:LogPath, reason=no_logs)"
            exit 3
        }

        $hasTrace = @($lines | Where-Object { $_ -match 'bindResources:' -or $_ -match 'TRACE_BG_CELLS_ENABLED' })
        if ($hasTrace.Count -eq 0) {
            Log "FAIL: trace not active (cp_diag='$traceDiag', log_path=$script:LogPath, reason=no_trace_lines)"
            exit 4
        }

        $unbound = @($lines | Where-Object {
            $_ -match 'extra buffers present but unbound' -or
            $_ -match 'extra buffers present but no SRV binding provided'
        })
        if ($unbound.Count -gt 0) {
            Log "FAIL: detected unbound bg_cells path ($($unbound.Count) hits)."
            Log "This FAIL is expected before the #146 fix lands."
            exit 1
        }
        Log "PASS: fallback log-based trace detection succeeded (cp_diag not conclusive)."
        exit 0
    }

    Log "PASS: CP diagnostics confirm trace activity (bind_counter=$bindCounter)."
    exit 0
}
finally {
    Stop-Ghostty
}
