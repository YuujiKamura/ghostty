$ErrorActionPreference = "Stop"

. "$PSScriptRoot\winui3-test-lib.ps1"

function Get-Phase6RepoRoot {
    return (Split-Path -Parent $PSScriptRoot)
}

function Get-Phase6OutputDir {
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$OutDir)
    $path = Join-Path $RepoRoot $OutDir
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function New-Phase6Env {
    param([hashtable]$Extra = @{})

    $envMap = @{
        "GHOSTTY_CONTROL_PLANE" = "1"
        "GHOSTTY_WINUI3_ENABLE_TABVIEW" = "1"
        "GHOSTTY_WINUI3_USE_IXAML_METADATA_PROVIDER" = "1"
        "GHOSTTY_WINUI3_ENABLE_XAML_RESOURCES" = "1"
        "GHOSTTY_WINUI3_ENABLE_TABVIEW_HANDLERS" = "1"
        "GHOSTTY_WINUI3_TABVIEW_EMPTY" = "0"
        "GHOSTTY_WINUI3_TABVIEW_ITEM_NO_CONTENT" = "0"
        "GHOSTTY_WINUI3_TABVIEW_APPEND_ITEM" = "1"
        "GHOSTTY_WINUI3_TABVIEW_SELECT_FIRST" = "1"
    }

    foreach ($key in $Extra.Keys) {
        $envMap[$key] = [string]$Extra[$key]
    }

    return $envMap
}

function Set-Phase6Env {
    param([Parameter(Mandatory)][hashtable]$Map)

    $backup = @{}
    foreach ($key in $Map.Keys) {
        $backup[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
        [Environment]::SetEnvironmentVariable($key, [string]$Map[$key], "Process")
    }
    return $backup
}

function Restore-Phase6Env {
    param([Parameter(Mandatory)][hashtable]$Backup)

    foreach ($key in $Backup.Keys) {
        [Environment]::SetEnvironmentVariable($key, $Backup[$key], "Process")
    }
}

function Resolve-Phase6ExePath {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$ExePath,
        [ValidateSet("winui3","win32")][string]$Runtime = "winui3",
        [string]$Optimize = "ReleaseSafe",
        [switch]$NoBuild
    )

    if ($ExePath) {
        if (-not (Test-Path $ExePath)) {
            throw "ghostty.exe not found: $ExePath"
        }
        return $ExePath
    }

    if (-not $NoBuild) {
        return (Build-AndStageGhosttyExe -RepoRoot $RepoRoot -Runtime $Runtime -Optimize $Optimize)
    }

    $candidates = @(
        (Get-StagedGhosttyExePath -RepoRoot $RepoRoot -Runtime $Runtime),
        (Join-Path $RepoRoot "zig-out-winui3\bin\ghostty.exe"),
        (Join-Path $RepoRoot "zig-out\bin\ghostty.exe")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw "No WinUI3 executable found. Run without -NoBuild first or pass -ExePath."
}

function Resolve-Phase6WorkingDirectory {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$ExePath
    )

    if ($ExePath -like "*\zig-out\bin\ghostty.exe" -or $ExePath -like "*\zig-out-winui3\bin\ghostty.exe") {
        return $RepoRoot
    }

    return (Split-Path -Parent $ExePath)
}

function Find-Phase6GhosttyWindow {
    param(
        [Parameter(Mandatory)][pscustomobject]$Session,
        [int]$TimeoutMs = 20000
    )

    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    do {
        try { $Session.Process.Refresh() } catch {}
        if ($Session.Process.HasExited) {
            throw "ghostty exited before exposing a main window (exit=$(Format-ExitCode $Session.Process.ExitCode))"
        }
        if ($Session.Process.MainWindowHandle -ne 0) {
            $hwnd = [IntPtr]$Session.Process.MainWindowHandle
            if ([Win32]::IsWindowVisible($hwnd)) {
                return $hwnd
            }
        }
        Start-Sleep -Milliseconds 120
    } while ((Get-Date) -lt $deadline)

    try {
        return Find-GhosttyWindow -StderrPath $Session.DebugLogPath -TimeoutMs 2000
    } catch {}

    return (Find-GhosttyWindow -StderrPath $Session.StderrPath -TimeoutMs 2000)
}

function Get-Phase6ControlSessionsRoot {
    return (Join-Path $env:LOCALAPPDATA "ghostty\control-plane\winui3\sessions")
}

function Read-Phase6SessionFile {
    param([Parameter(Mandatory)][string]$Path)

    $map = @{}
    foreach ($line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        if ($line -match '^(?<k>[^=]+)=(?<v>.*)$') {
            $map[$Matches.k] = $Matches.v
        }
    }
    return $map
}

function Wait-Phase6ControlSession {
    param(
        [Parameter(Mandatory)][int]$TargetPid,
        [int]$TimeoutMs = 15000
    )

    $root = Get-Phase6ControlSessionsRoot
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)

    do {
        if (Test-Path $root) {
            foreach ($file in Get-ChildItem -LiteralPath $root -Filter "*.session" -File -ErrorAction SilentlyContinue) {
                try {
                    $map = Read-Phase6SessionFile -Path $file.FullName
                    if (-not $map.ContainsKey("pid")) {
                        continue
                    }
                    if ([int]$map.pid -ne $TargetPid) {
                        continue
                    }
                    return [pscustomobject]@{
                        SessionName = $map.session_name
                        SafeSessionName = $map.safe_session_name
                        PipeName = $map.pipe_name
                        Pid = [int]$map.pid
                        Hwnd = $map.hwnd
                        LogFile = $map.log_file
                        File = $file.FullName
                    }
                } catch {}
            }
        }
        Start-Sleep -Milliseconds 150
    } while ((Get-Date) -lt $deadline)

    throw "control-plane session was not registered for pid $TargetPid"
}

function Invoke-Phase6Control {
    param(
        [Parameter(Mandatory)][pscustomobject]$Control,
        [ValidateSet("PING","STATE","TAIL","INPUT","LIST_TABS","NEW_TAB","CLOSE_TAB","SWITCH_TAB","FOCUS")][string]$Type = "PING",
        [string]$Text = "",
        [string]$From = "phase6",
        [int]$Lines = 20,
        [int]$TabIndex = -1
    )

    $message = switch ($Type) {
        "PING" { "PING" }
        "STATE" {
            if ($TabIndex -ge 0) { "STATE|$TabIndex" } else { "STATE" }
        }
        "TAIL" { "TAIL|$Lines" }
        "INPUT" {
            $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Text))
            "INPUT|$From|$encoded"
        }
        "LIST_TABS" { "LIST_TABS" }
        "NEW_TAB" { "NEW_TAB" }
        "CLOSE_TAB" {
            if ($TabIndex -ge 0) { "CLOSE_TAB|$TabIndex" } else { "CLOSE_TAB" }
        }
        "SWITCH_TAB" {
            if ($TabIndex -lt 0) {
                throw "-TabIndex is required for SWITCH_TAB"
            }
            "SWITCH_TAB|$TabIndex"
        }
        "FOCUS" { "FOCUS" }
    }

    $client = [System.IO.Pipes.NamedPipeClientStream]::new(
        ".",
        $Control.PipeName,
        [System.IO.Pipes.PipeDirection]::InOut
    )

    try {
        $client.Connect(3000)
        $writer = [System.IO.StreamWriter]::new($client)
        $writer.AutoFlush = $true
        $reader = [System.IO.StreamReader]::new($client)
        try {
            $writer.WriteLine($message)
            return $reader.ReadToEnd()
        } finally {
            if ($reader) {
                try { $reader.Dispose() } catch {}
            }
            if ($writer) {
                try { $writer.Dispose() } catch {}
            }
        }
    } finally {
        if ($client) {
            try { $client.Dispose() } catch {}
        }
    }
}

function Invoke-Phase6ShellCommand {
    param(
        [Parameter(Mandatory)][pscustomobject]$Control,
        [Parameter(Mandatory)][string]$Command,
        [string]$From = "phase6"
    )

    $text = if ($Command.EndsWith("`r") -or $Command.EndsWith("`n")) {
        $Command
    } else {
        $Command + "`r"
    }

    return (Invoke-Phase6Control -Control $Control -Type INPUT -Text $text -From $From)
}

function Parse-Phase6StateText {
    param([Parameter(Mandatory)][string]$Text)

    $lines = @(
        ($Text -replace "`r", "") -split "`n" |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($lines.Count -eq 0) {
        throw "STATE reply was empty"
    }

    $parts = $lines[0] -split '\|'
    if ($parts.Length -lt 5 -or $parts[0] -ne "STATE") {
        throw "unexpected STATE reply: $($lines[0])"
    }

    $result = [ordered]@{
        Raw = $lines[0]
        Session = $parts[1]
        Pid = [int]$parts[2]
        Hwnd = $parts[3]
        Title = $parts[4]
        Prompt = "0"
        Selection = "0"
        Pwd = ""
        TabCount = 0
        ActiveTab = 0
    }

    for ($i = 5; $i -lt $parts.Length; $i++) {
        if ($parts[$i] -match '^(?<k>[^=]+)=(?<v>.*)$') {
            switch ($Matches.k) {
                "prompt" { $result.Prompt = $Matches.v }
                "selection" { $result.Selection = $Matches.v }
                "pwd" { $result.Pwd = $Matches.v }
                "tab_count" { $result.TabCount = [int]$Matches.v }
                "active_tab" { $result.ActiveTab = [int]$Matches.v }
            }
        }
    }

    return [pscustomobject]$result
}

function Get-Phase6State {
    param(
        [Parameter(Mandatory)][pscustomobject]$Control,
        [int]$TabIndex = -1
    )

    $reply = Invoke-Phase6Control -Control $Control -Type STATE -TabIndex $TabIndex
    return (Parse-Phase6StateText -Text $reply)
}

function Parse-Phase6TabsText {
    param([Parameter(Mandatory)][string]$Text)

    $lines = @(
        ($Text -replace "`r", "") -split "`n" |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($lines.Count -eq 0) {
        throw "LIST_TABS reply was empty"
    }

    $header = $lines[0] -split '\|'
    if ($header.Length -lt 3 -or $header[0] -ne "LIST_TABS") {
        throw "unexpected LIST_TABS reply: $($lines[0])"
    }

    $tabs = @()
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '^TAB\|(?<index>\d+)\|(?<title>[^|]*)\|(?<rest>.*)$') {
            continue
        }

        $tab = [ordered]@{
            Index = [int]$Matches.index
            Title = $Matches.title
            Prompt = "0"
            Selection = "0"
            Pwd = ""
        }

        foreach ($part in ($Matches.rest -split '\|')) {
            if ($part -match '^(?<k>[^=]+)=(?<v>.*)$') {
                switch ($Matches.k) {
                    "prompt" { $tab.Prompt = $Matches.v }
                    "selection" { $tab.Selection = $Matches.v }
                    "pwd" { $tab.Pwd = $Matches.v }
                }
            }
        }

        $tabs += [pscustomobject]$tab
    }

    return [pscustomobject]@{
        Raw = $Text
        TabCount = [int]$header[1]
        ActiveTab = [int]$header[2]
        Tabs = $tabs
    }
}

function Get-Phase6Tabs {
    param([Parameter(Mandatory)][pscustomobject]$Control)
    return (Parse-Phase6TabsText -Text (Invoke-Phase6Control -Control $Control -Type LIST_TABS))
}

function Wait-Phase6PromptReady {
    param(
        [Parameter(Mandatory)][pscustomobject]$Control,
        [int]$TimeoutMs = 15000
    )

    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    do {
        try {
            $state = Get-Phase6State -Control $Control
            if ($state.Prompt -eq "1") {
                return $state
            }
        } catch {}
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)

    throw "shell prompt did not become ready within ${TimeoutMs}ms"
}

function Wait-Phase6TabCount {
    param(
        [Parameter(Mandatory)][pscustomobject]$Control,
        [Parameter(Mandatory)][int]$Expected,
        [int]$TimeoutMs = 10000
    )

    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    do {
        try {
            $tabs = Get-Phase6Tabs -Control $Control
            if ($tabs.TabCount -eq $Expected) {
                return $tabs
            }
        } catch {}
        Start-Sleep -Milliseconds 150
    } while ((Get-Date) -lt $deadline)

    throw "tab count did not reach $Expected within ${TimeoutMs}ms"
}

function Wait-Phase6ActiveTab {
    param(
        [Parameter(Mandatory)][pscustomobject]$Control,
        [Parameter(Mandatory)][int]$Expected,
        [int]$TimeoutMs = 10000
    )

    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    do {
        try {
            $state = Get-Phase6State -Control $Control
            if ($state.ActiveTab -eq $Expected) {
                return $state
            }
        } catch {}
        Start-Sleep -Milliseconds 150
    } while ((Get-Date) -lt $deadline)

    throw "active tab did not reach $Expected within ${TimeoutMs}ms"
}

function Wait-Phase6TailContains {
    param(
        [Parameter(Mandatory)][pscustomobject]$Control,
        [Parameter(Mandatory)][string]$Text,
        [int]$TimeoutMs = 12000,
        [int]$Lines = 60
    )

    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    do {
        try {
            $tail = Invoke-Phase6Control -Control $Control -Type TAIL -Lines $Lines
            if ($tail.Contains($Text)) {
                return $tail
            }
        } catch {}
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)

    throw "TAIL did not contain '$Text' within ${TimeoutMs}ms"
}

function Wait-Phase6StateTitle {
    param(
        [Parameter(Mandatory)][pscustomobject]$Control,
        [Parameter(Mandatory)][string]$Text,
        [int]$TimeoutMs = 12000
    )

    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    do {
        try {
            $state = Get-Phase6State -Control $Control
            if ($state.Title.Contains($Text)) {
                return $state
            }
        } catch {}
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)

    throw "STATE title did not contain '$Text' within ${TimeoutMs}ms"
}

function Wait-Phase6TabTitle {
    param(
        [Parameter(Mandatory)][pscustomobject]$Control,
        [Parameter(Mandatory)][int]$TabIndex,
        [Parameter(Mandatory)][string]$Text,
        [int]$TimeoutMs = 12000
    )

    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    do {
        try {
            $tabs = Get-Phase6Tabs -Control $Control
            foreach ($tab in $tabs.Tabs) {
                if ($tab.Index -eq $TabIndex -and $tab.Title.Contains($Text)) {
                    return $tab
                }
            }
        } catch {}
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)

    throw "tab $TabIndex title did not contain '$Text' within ${TimeoutMs}ms"
}

function Wait-Phase6LogLineAny {
    param(
        [Parameter(Mandatory)][pscustomobject]$Session,
        [Parameter(Mandatory)][string]$Pattern,
        [int]$TimeoutMs = 10000
    )

    try {
        return Wait-LogLine -Path $Session.DebugLogPath -Pattern $Pattern -TimeoutMs $TimeoutMs
    } catch {}

    return (Wait-LogLine -Path $Session.StderrPath -Pattern $Pattern -TimeoutMs $TimeoutMs)
}

function Has-Phase6LogLineAny {
    param(
        [Parameter(Mandatory)][pscustomobject]$Session,
        [Parameter(Mandatory)][string]$Pattern
    )

    $debugHit = (Test-Path $Session.DebugLogPath) -and
        [bool](Select-String -Path $Session.DebugLogPath -Pattern $Pattern -SimpleMatch -ErrorAction SilentlyContinue)
    if ($debugHit) {
        return $true
    }

    return ((Test-Path $Session.StderrPath) -and
        [bool](Select-String -Path $Session.StderrPath -Pattern $Pattern -SimpleMatch -ErrorAction SilentlyContinue))
}

function Ensure-Phase6Foreground {
    param(
        [Parameter(Mandatory)][pscustomobject]$Session,
        [int]$TimeoutMs = 5000
    )

    if ($Session.Control) {
        try { Invoke-Phase6Control -Control $Session.Control -Type FOCUS | Out-Null } catch {}
    }

    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    do {
        [Win32]::ForceForegroundWindow($Session.Hwnd) | Out-Null
        try { Send-MouseClickCenter -Hwnd $Session.Hwnd } catch {}
        Start-Sleep -Milliseconds 150
        if ([Win32]::GetForegroundWindow() -eq $Session.Hwnd) {
            return $true
        }
    } while ((Get-Date) -lt $deadline)

    return $false
}

function Get-Phase6WindowRect {
    param([Parameter(Mandatory)][IntPtr]$Hwnd)

    $rect = New-Object RECT
    if (-not [Win32]::GetWindowRect($Hwnd, [ref]$rect)) {
        throw "GetWindowRect failed for HWND=0x$($Hwnd.ToString('X'))"
    }

    return [pscustomobject]@{
        Left = $rect.Left
        Top = $rect.Top
        Right = $rect.Right
        Bottom = $rect.Bottom
        Width = ($rect.Right - $rect.Left)
        Height = ($rect.Bottom - $rect.Top)
    }
}

function Set-Phase6WindowSize {
    param(
        [Parameter(Mandatory)][pscustomobject]$Session,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height
    )

    $rect = Get-Phase6WindowRect -Hwnd $Session.Hwnd
    $ok = [Win32]::SetWindowPos(
        $Session.Hwnd,
        [IntPtr]::Zero,
        $rect.Left,
        $rect.Top,
        $Width,
        $Height,
        [Win32]::SWP_NOZORDER
    )
    if (-not $ok) {
        throw "SetWindowPos failed for ${Width}x${Height}"
    }
}

function Get-Phase6HeaderMetrics {
    param([Parameter(Mandatory)][System.Drawing.Bitmap]$Bitmap)

    $width = $Bitmap.Width
    $height = $Bitmap.Height
    $bandHeight = [Math]::Min(96, [Math]::Max(24, [int]($height * 0.14)))
    $step = 4
    $sum = 0.0
    $sum2 = 0.0
    $count = 0
    $nonBlack = 0

    for ($y = 0; $y -lt $bandHeight; $y += $step) {
        for ($x = 0; $x -lt $width; $x += $step) {
            $c = $Bitmap.GetPixel($x, $y)
            $lum = (0.2126 * $c.R) + (0.7152 * $c.G) + (0.0722 * $c.B)
            $sum += $lum
            $sum2 += ($lum * $lum)
            if (($c.R + $c.G + $c.B) -gt 12) {
                $nonBlack++
            }
            $count++
        }
    }

    if ($count -le 0) {
        return [pscustomobject]@{
            HeaderLikelyVisible = $false
            LumaStdDev = 0.0
            NonBlackRatio = 0.0
        }
    }

    $mean = $sum / $count
    $variance = ($sum2 / $count) - ($mean * $mean)
    if ($variance -lt 0) {
        $variance = 0
    }
    $std = [Math]::Sqrt($variance)
    $nonBlackRatio = [double]$nonBlack / [double]$count

    return [pscustomobject]@{
        HeaderLikelyVisible = (($std -ge 6.0) -and ($nonBlackRatio -ge 0.08))
        LumaStdDev = [Math]::Round($std, 3)
        NonBlackRatio = [Math]::Round($nonBlackRatio, 4)
    }
}

function Save-Phase6Snapshot {
    param(
        [Parameter(Mandatory)][pscustomobject]$Session,
        [Parameter(Mandatory)][string]$Path
    )

    $bmp = Get-WindowVisualSnapshot -Hwnd $Session.Hwnd
    try {
        $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
        return (Get-Phase6HeaderMetrics -Bitmap $bmp)
    } finally {
        $bmp.Dispose()
    }
}

function Start-Phase6Session {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$ExePath,
        [Parameter(Mandatory)][string]$OutDir,
        [Parameter(Mandatory)][hashtable]$Env
    )

    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    $tmpDir = Join-Path $OutDir "run"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    Clear-OldLogs -TmpDir $tmpDir -KeepCount 10

    $debugLogPath = Join-Path $env:USERPROFILE "ghostty_debug.log"
    "" | Set-Content -Path $debugLogPath -Encoding utf8

    $backup = Set-Phase6Env -Map $Env
    try {
        $baseSession = Start-Ghostty `
            -ExePath $ExePath `
            -TmpDir $tmpDir `
            -WorkingDirectory (Resolve-Phase6WorkingDirectory -RepoRoot $RepoRoot -ExePath $ExePath)
    } finally {
        Restore-Phase6Env -Backup $backup
    }

    $session = [pscustomobject]@{
        Process = $baseSession.Process
        StderrPath = $baseSession.StderrPath
        StartTime = $baseSession.StartTime
        RepoRoot = $RepoRoot
        DebugLogPath = $debugLogPath
        OutDir = $OutDir
        Hwnd = [IntPtr]::Zero
        Control = $null
    }

    $session.Hwnd = Find-Phase6GhosttyWindow -Session $session -TimeoutMs 20000
    $session.Control = Wait-Phase6ControlSession -TargetPid $session.Process.Id -TimeoutMs 15000
    return $session
}

function Stop-Phase6Session {
    param(
        [Parameter(Mandatory)][pscustomobject]$Session,
        [Parameter(Mandatory)][string]$ArtifactPrefix
    )

    $exitCode = $null
    if ($Session.Process -and -not $Session.Process.HasExited) {
        $exitCode = Stop-Ghostty -Session $Session -TimeoutMs 5000
    } elseif ($Session.Process) {
        $exitCode = $Session.Process.ExitCode
    } else {
        $exitCode = -1
    }

    Start-Sleep -Milliseconds 200

    $stderrCopy = Join-Path $Session.OutDir "$ArtifactPrefix.stderr.log"
    $debugCopy = Join-Path $Session.OutDir "$ArtifactPrefix.debug.log"

    if (Test-Path $Session.StderrPath) {
        Copy-Item -Path $Session.StderrPath -Destination $stderrCopy -Force
    }
    if (Test-Path $Session.DebugLogPath) {
        Copy-Item -Path $Session.DebugLogPath -Destination $debugCopy -Force
    }

    return [pscustomobject]@{
        ExitCode = [int]$exitCode
        StderrLog = $stderrCopy
        DebugLog = $debugCopy
    }
}
