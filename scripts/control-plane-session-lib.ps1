function Read-ControlPlaneSessionMap {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $map = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^(?<k>[^=]+)=(?<v>.*)$') {
            $map[$Matches.k] = $Matches.v
        }
    }

    return $map
}

function Test-ControlPlaneSessionProcessAlive {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Map
    )

    $pidValue = 0
    if (-not [int]::TryParse([string]$Map.pid, [ref]$pidValue)) {
        return $false
    }

    return [bool](Get-Process -Id $pidValue -ErrorAction SilentlyContinue)
}

function Remove-ControlPlaneSessionFileIfPresent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    } catch {}
}

function Get-ControlPlaneSessionEntries {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    if (-not (Test-Path $Root)) {
        return @()
    }

    $entries = foreach ($file in Get-ChildItem -LiteralPath $Root -Filter '*.session' -File | Sort-Object LastWriteTimeUtc -Descending) {
        $map = Read-ControlPlaneSessionMap -Path $file.FullName
        if (-not (Test-ControlPlaneSessionProcessAlive -Map $map)) {
            Remove-ControlPlaneSessionFileIfPresent -Path $file.FullName
            continue
        }

        [pscustomobject]@{
            Session = $map.session_name
            SafeSession = $map.safe_session_name
            Pid = $map.pid
            Hwnd = $map.hwnd
            PipeName = $map.pipe_name
            Log = $map.log_file
            File = $file.FullName
        }
    }

    return @($entries)
}

function Find-ControlPlaneSessionEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$SessionName
    )

    foreach ($entry in Get-ControlPlaneSessionEntries -Root $Root) {
        if ($entry.Session -eq $SessionName -or $entry.SafeSession -eq $SessionName -or $entry.PipeName -eq $SessionName) {
            return $entry
        }
    }

    return $null
}
