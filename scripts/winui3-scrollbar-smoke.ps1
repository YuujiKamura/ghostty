param(
    [ValidateSet("winui3")][string]$Runtime = "winui3",
    [switch]$NoBuild,
    [string]$CommandText = 'cmd /c for /l %i in (1,1,400) do @echo scrollbar-smoke-%i',
    [int]$WarmupMs = 2500,
    [int]$WorkMs = 6000,
    [string]$OutDir = "tmp/scrollbar-smoke",
    [double]$MinRightBandDiff = 0.05,
    [double]$MinScrollbarWidth = 10.0,
    [double]$MinScrollbarHeight = 100.0
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\winui3-test-lib.ps1"

$repoRoot = Split-Path -Parent $PSScriptRoot
$debugLogPath = Join-Path $repoRoot "debug.log"
$tmpDir = Join-Path $repoRoot "tmp"
$outAbs = Join-Path $repoRoot $OutDir
New-Item -ItemType Directory -Path $outAbs -Force | Out-Null

function Find-GhosttyWindowAny {
    param(
        [Parameter(Mandatory)][pscustomobject]$Session,
        [int]$TimeoutMs = 20000
    )

    try {
        return Find-GhosttyWindow -StderrPath $Session.StderrPath -TimeoutMs 1500
    } catch {}

    $line = Wait-LogLine -Path $debugLogPath -Pattern "step 4 OK: HWND=0x" -TimeoutMs $TimeoutMs
    if ($line -match "HWND=0x([0-9a-fA-F]+)") {
        $hwnd = [IntPtr][System.Convert]::ToInt64($Matches[1], 16)
        if ([Win32]::IsWindowVisible($hwnd)) { return $hwnd }
    }
    throw "HWND not found from stderr/debug log"
}

function Find-GhosttyInputWindowAny {
    param(
        [Parameter(Mandatory)][pscustomobject]$Session,
        [int]$TimeoutMs = 20000
    )

    $line = $null
    try {
        $line = Wait-LogLine -Path $Session.StderrPath -Pattern "input HWND=0x" -TimeoutMs 1500
    } catch {}

    if (-not $line) {
        $line = Wait-LogLine -Path $debugLogPath -Pattern "input HWND=0x" -TimeoutMs $TimeoutMs
    }

    if ($line -match "input HWND=0x([0-9a-fA-F]+)") {
        return [IntPtr][System.Convert]::ToInt64($Matches[1], 16)
    }
    throw "input HWND not found from stderr/debug log"
}

function Get-UiaScrollBarMetrics {
    param(
        [Parameter(Mandatory)][IntPtr]$Hwnd
    )

    $result = [PSCustomObject]@{
        available = $false
        count = 0
        items = @()
    }

    try {
        Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop | Out-Null
        Add-Type -AssemblyName UIAutomationTypes -ErrorAction Stop | Out-Null

        $root = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
        if ($null -eq $root) { return $result }

        $condScrollBar = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::ScrollBar
        )

        $elements = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condScrollBar)
        $items = @()
        for ($i = 0; $i -lt $elements.Count; $i++) {
            $el = $elements.Item($i)
            $rect = $el.Current.BoundingRectangle
            $range = $null
            $rangeObj = $null
            if ($el.TryGetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern, [ref]$rangeObj)) {
                $range = [System.Windows.Automation.RangeValuePattern]$rangeObj
            }

            $items += [PSCustomObject]@{
                name = $el.Current.Name
                automation_id = $el.Current.AutomationId
                is_offscreen = $el.Current.IsOffscreen
                x = [Math]::Round($rect.X, 2)
                y = [Math]::Round($rect.Y, 2)
                width = [Math]::Round($rect.Width, 2)
                height = [Math]::Round($rect.Height, 2)
                range_min = if ($range) { [Math]::Round($range.Current.Minimum, 2) } else { $null }
                range_max = if ($range) { [Math]::Round($range.Current.Maximum, 2) } else { $null }
                range_value = if ($range) { [Math]::Round($range.Current.Value, 2) } else { $null }
                range_large = if ($range) { [Math]::Round($range.Current.LargeChange, 2) } else { $null }
            }
        }

        $result.available = $true
        $result.count = $items.Count
        $result.items = $items
        return $result
    } catch {
        return $result
    }
}

function Get-LatestScrollbarSyncMetrics {
    param(
        [Parameter(Mandatory)][string]$LogPath
    )

    if (-not (Test-Path $LogPath)) { return $null }

    $line = Get-Content -Path $LogPath -ErrorAction SilentlyContinue |
        Select-String -Pattern "scrollbar ui sync: orientation=" |
        Select-Object -Last 1
    if (-not $line) { return $null }

    $text = $line.Line
    if ($text -match 'orientation=(?<orientation>-?\d+)\s+viewport=(?<viewport>-?\d+(\.\d+)?)\s+actual=(?<width>-?\d+(\.\d+)?)x(?<height>-?\d+(\.\d+)?)\s+visibility=(?<visibility>-?\d+)\s+max=(?<max>-?\d+(\.\d+)?)\s+value=(?<value>-?\d+(\.\d+)?)\s+len=(?<len>-?\d+(\.\d+)?)') {
        return [PSCustomObject]@{
            line = $text
            orientation = [int]$Matches.orientation
            viewport = [double]$Matches.viewport
            actual_width = [double]$Matches.width
            actual_height = [double]$Matches.height
            visibility = [int]$Matches.visibility
            max = [double]$Matches.max
            value = [double]$Matches.value
            len = [double]$Matches.len
        }
    }

    return [PSCustomObject]@{ line = $text }
}

function Get-RightBandDiffRatio {
    param(
        [Parameter(Mandatory)][System.Drawing.Bitmap]$Before,
        [Parameter(Mandatory)][System.Drawing.Bitmap]$After,
        [int]$BandWidth = 28,
        [int]$SampleStep = 4,
        [int]$ColorThreshold = 24
    )

    $w = [Math]::Min($Before.Width, $After.Width)
    $h = [Math]::Min($Before.Height, $After.Height)
    if ($w -le 0 -or $h -le 0) { return 0.0 }

    $startX = [Math]::Max(0, $w - $BandWidth)
    $changed = 0
    $total = 0

    for ($y = 0; $y -lt $h; $y += $SampleStep) {
        for ($x = $startX; $x -lt $w; $x += $SampleStep) {
            $c1 = $Before.GetPixel($x, $y)
            $c2 = $After.GetPixel($x, $y)
            $delta = [Math]::Abs([int]$c1.R - [int]$c2.R) +
                     [Math]::Abs([int]$c1.G - [int]$c2.G) +
                     [Math]::Abs([int]$c1.B - [int]$c2.B)
            if ($delta -ge $ColorThreshold) { $changed++ }
            $total++
        }
    }

    if ($total -le 0) { return 0.0 }
    return ([double]$changed / [double]$total)
}

function Test-ScrollbarAcceptance {
    param(
        [Parameter(Mandatory)]$Summary,
        [double]$MinRightBandDiff = 0.05,
        [double]$MinScrollbarWidth = 10.0,
        [double]$MinScrollbarHeight = 100.0
    )

    $failures = [System.Collections.Generic.List[string]]::new()
    $sync = $Summary.scrollbar_sync

    if (-not $sync) {
        $failures.Add("missing scrollbar_sync metrics from debug.log")
    } else {
        if ($sync.orientation -ne 1) {
            $failures.Add("expected vertical orientation=1, got $($sync.orientation)")
        }
        if ($sync.visibility -ne 0) {
            $failures.Add("expected visibility=0 (Visible), got $($sync.visibility)")
        }
        if ($sync.actual_width -lt $MinScrollbarWidth) {
            $failures.Add("expected actual_width >= $MinScrollbarWidth, got $($sync.actual_width)")
        }
        if ($sync.actual_height -lt $MinScrollbarHeight) {
            $failures.Add("expected actual_height >= $MinScrollbarHeight, got $($sync.actual_height)")
        }
        if ($sync.max -le 0) {
            $failures.Add("expected max > 0 after scrollback generation, got $($sync.max)")
        }
        if ($sync.value -lt 0) {
            $failures.Add("expected non-negative value, got $($sync.value)")
        }
    }

    if ($Summary.right_band_diff_ratio -lt $MinRightBandDiff) {
        $failures.Add("expected right_band_diff_ratio >= $MinRightBandDiff, got $($Summary.right_band_diff_ratio)")
    }

    [PSCustomObject]@{
        passed = ($failures.Count -eq 0)
        failures = @($failures)
        thresholds = [PSCustomObject]@{
            min_right_band_diff = $MinRightBandDiff
            min_scrollbar_width = $MinScrollbarWidth
            min_scrollbar_height = $MinScrollbarHeight
        }
    }
}

if (-not $NoBuild) {
    Push-Location $repoRoot
    try {
        & zig build "-Dapp-runtime=$Runtime" "-Drenderer=d3d11"
        if ($LASTEXITCODE -ne 0) {
            throw "Build failed (exit code $LASTEXITCODE)"
        }
    } finally {
        Pop-Location
    }
}

$exePath = Join-Path $repoRoot "zig-out\bin\ghostty.exe"
$exeWorkDir = Join-Path $repoRoot "zig-out\bin"
if (-not (Test-Path $exePath)) {
    throw "Executable not found after build: $exePath"
}

$beforePath = Join-Path $outAbs "before.png"
$afterPath = Join-Path $outAbs "after.png"
$jsonPath = Join-Path $outAbs "summary.json"
$mdPath = Join-Path $outAbs "summary.md"

"" | Set-Content -Path $debugLogPath -Encoding utf8
$session = $null

try {
    $session = Start-Ghostty -ExePath $exePath -TmpDir $tmpDir -WorkingDirectory $exeWorkDir
    $hwnd = Find-GhosttyWindowAny -Session $session -TimeoutMs 20000
    $inputHwnd = Find-GhosttyInputWindowAny -Session $session -TimeoutMs 20000

    Start-Sleep -Milliseconds $WarmupMs

    $beforeBmp = Get-WindowVisualSnapshot -Hwnd $hwnd
    try {
        $beforeBmp.Save($beforePath, [System.Drawing.Imaging.ImageFormat]::Png)
        $uiaBefore = Get-UiaScrollBarMetrics -Hwnd $hwnd

        [Win32]::PostUnicodeText($inputHwnd, $CommandText)
        Start-Sleep -Milliseconds 60
        [Win32]::PostEnter($inputHwnd)

        Start-Sleep -Milliseconds $WorkMs

        $afterBmp = Get-WindowVisualSnapshot -Hwnd $hwnd
        try {
            $afterBmp.Save($afterPath, [System.Drawing.Imaging.ImageFormat]::Png)
            $uiaAfter = Get-UiaScrollBarMetrics -Hwnd $hwnd

            $fullDiff = Get-VisualDiffRatioBetween -Before $beforeBmp -After $afterBmp
            $rightBandDiff = Get-RightBandDiffRatio -Before $beforeBmp -After $afterBmp

            $summary = [PSCustomObject]@{
                hwnd = ('0x{0:X}' -f $hwnd.ToInt64())
                input_hwnd = ('0x{0:X}' -f $inputHwnd.ToInt64())
                command = $CommandText
                before_screenshot = $beforePath
                after_screenshot = $afterPath
                full_diff_ratio = [Math]::Round($fullDiff, 4)
                right_band_diff_ratio = [Math]::Round($rightBandDiff, 4)
                uia_before = $uiaBefore
                uia_after = $uiaAfter
                scrollbar_sync = Get-LatestScrollbarSyncMetrics -LogPath $debugLogPath
                stderr_log = $session.StderrPath
                debug_log = $debugLogPath
            }

            $acceptance = Test-ScrollbarAcceptance -Summary $summary `
                -MinRightBandDiff $MinRightBandDiff `
                -MinScrollbarWidth $MinScrollbarWidth `
                -MinScrollbarHeight $MinScrollbarHeight
            $summary | Add-Member -NotePropertyName acceptance -NotePropertyValue $acceptance

            $summary | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8

            $md = @()
            $md += "# WinUI3 Scrollbar Smoke"
            $md += ""
            $md += "- hwnd: $($summary.hwnd)"
            $md += "- input_hwnd: $($summary.input_hwnd)"
            $md += "- command: " + $summary.command
            $md += "- full_diff_ratio: $($summary.full_diff_ratio)"
            $md += "- right_band_diff_ratio: $($summary.right_band_diff_ratio)"
            $md += "- before_screenshot: $($summary.before_screenshot)"
            $md += "- after_screenshot: $($summary.after_screenshot)"
            $md += "- stderr_log: $($summary.stderr_log)"
            $md += "- debug_log: $($summary.debug_log)"
            if ($summary.scrollbar_sync) {
                $md += "- scrollbar_sync: orientation=$($summary.scrollbar_sync.orientation) viewport=$($summary.scrollbar_sync.viewport) actual=$($summary.scrollbar_sync.actual_width)x$($summary.scrollbar_sync.actual_height) visibility=$($summary.scrollbar_sync.visibility) max=$($summary.scrollbar_sync.max) value=$($summary.scrollbar_sync.value) len=$($summary.scrollbar_sync.len)"
            }
            $md += "- acceptance_passed: $($summary.acceptance.passed)"
            $md += ""
            $md += "## Acceptance"
            foreach ($failure in $summary.acceptance.failures) {
                $md += "- FAIL: $failure"
            }
            if ($summary.acceptance.failures.Count -eq 0) {
                $md += "- PASS"
            }
            $md += ""
            $md += "## UIA Before"
            foreach ($item in $uiaBefore.items) {
                $md += "- name=`"$($item.name)`" offscreen=$($item.is_offscreen) rect=[$($item.x),$($item.y),$($item.width),$($item.height)] range=[$($item.range_min),$($item.range_value),$($item.range_max)]"
            }
            $md += ""
            $md += "## UIA After"
            foreach ($item in $uiaAfter.items) {
                $md += "- name=`"$($item.name)`" offscreen=$($item.is_offscreen) rect=[$($item.x),$($item.y),$($item.width),$($item.height)] range=[$($item.range_min),$($item.range_value),$($item.range_max)]"
            }
            $md | Set-Content -Path $mdPath -Encoding UTF8

            Write-Host "wrote: $jsonPath"
            Write-Host "wrote: $mdPath"
            Write-Host ("UIA scrollbars before={0} after={1}" -f $uiaBefore.count, $uiaAfter.count)
            Write-Host ("diff full={0} right_band={1}" -f $summary.full_diff_ratio, $summary.right_band_diff_ratio)
            Write-Host ("acceptance passed={0}" -f $summary.acceptance.passed)
            if (-not $summary.acceptance.passed) {
                foreach ($failure in $summary.acceptance.failures) {
                    Write-Error $failure
                }
                throw "WinUI3 scrollbar smoke acceptance failed"
            }
        } finally {
            $afterBmp.Dispose()
        }
    } finally {
        $beforeBmp.Dispose()
    }
}
finally {
    if ($session) {
        Stop-Ghostty -Session $session -TimeoutMs 3000 | Out-Null
    }
}
