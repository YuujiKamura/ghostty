param(
    [string]$ExePath,
    [int]$LaunchTimeoutMs = 20000,
    [switch]$BudgetReportOnly  # if set, never fails — useful for tracking trends without gating CI
)

# test-10-cold-start-perf.ps1
# Cold-start performance health check.
#
# Why this exists:
#   "計測するっていう考え方すら標準にない" — perf measurement should be a
#   continuous health gate, not an ad-hoc forensic activity. Like blood
#   pressure: take it routinely, flag clear regressions, don't trust feel.
#
# What this test does:
#   1. Launch ghostty.exe with KS_NO_ACTIVATE=visible (no focus theft)
#   2. Capture PID via Start-Process -PassThru
#   3. Read the per-PID debug log written by attachDebugConsole, which
#      contains PERF_INIT lines emitted by App.zig perfStep helpers
#   4. Wait for "content_ready (initXaml DONE)" — that line carries the
#      cumulative ms for the full cold-start path
#   5. Parse every PERF_INIT step into a (name, t, d) tuple
#   6. Always print the breakdown so trend regressions are visible even
#      when the budget hasn't been blown
#   7. Compare each tracked step + the total against a budget table.
#      Fail with a precise diff if any budget is exceeded.
#
# Budget philosophy (Debug build, single dev machine):
#   - Baselines captured 2026-05-06 on the dev workstation. Budgets are
#     ~2.4x baseline so transient noise / slower CI runners don't flake,
#     but a step that has genuinely doubled in cost will trip.
#   - Release builds will be much faster — the budgets are NOT meant to
#     match Release performance, they exist to stop unnoticed Debug-build
#     regressions during development.
#   - When a real optimisation lands, lower the corresponding budget to
#     keep ratchet pressure on. When the framework forces a step to grow
#     (e.g. WinAppSDK upgrade), raise the budget with a comment recording
#     the reason.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$testName = "test-10-cold-start-perf"

if (-not $ExePath) {
    $ExePath = Join-Path $PSScriptRoot "..\..\zig-out-winui3\bin\ghostty.exe"
}
$ExePath = (Resolve-Path $ExePath -ErrorAction Stop).Path

# Budget: { step name → max ms (cumulative since App.init entry, OR `step total` for total App.init / total) }
# Names match exactly the `step="..."` value emitted by perfStep().
# Special pseudo-steps:
#   "App.init total"       — total ms for App.init (parsed from the
#                            "PERF_INIT: total App.init = Xms" line)
#   "content_ready total"  — full cold-start to content_ready (parsed
#                            from the t= field of the content_ready step)
$budgets = [ordered]@{
    "bootstrap.init"                              = 300   # baseline ~125ms (heaviest single step in App.init)
    "App.init total"                              = 300   # baseline ~130ms
    "onApplicationStart entry"                    = 280   # baseline ~140ms (gap from init exit to XAML callback)
    "DesktopWindowXamlSource.initialize"          = 280   # baseline ~183ms
    "ShowWindow (window visible)"                 = 320   # baseline ~191ms
    "  createInitialSurfaceContent"               = 500   # baseline ~217ms — single largest step in entire startup
    "createWindowContent"                         = 600   # baseline ~226ms (sum of createWindowContent's children)
    "content_ready total"                         = 1000  # baseline ~421ms — initXaml return point
    "first Present"                               = 1100  # baseline ~363ms — first frame on screen (= what user perceives as "ready").
                                                          # NOTE: the IDC_APPSTARTING ("spinning") cursor that lingers ~2s after
                                                          # launch is NOT controlled by this metric. It's a side-effect of
                                                          # ghostty.exe being linked CONSOLE subsystem (see GhosttyExe.zig
                                                          # TODO). Windows shell can't observe input-idle for CONSOLE
                                                          # subsystem processes and falls back to a fixed cursor timeout.
                                                          # Even if first Present hits 50ms, the cursor will still linger
                                                          # until that OS timeout expires. Fix is at the subsystem layer
                                                          # (.Windows linkage), not in this code path.
}

# ----------------------------------------------------------------------
# Launch
# ----------------------------------------------------------------------
$env:KS_NO_ACTIVATE = "visible"  # prevent focus theft during test
$env:GHOSTTY_CONTROL_PLANE = $null
$env:WINDOWS_TERMINAL_CONTROL_PLANE = $null

Write-Host "[$testName] launching $ExePath ..." -ForegroundColor Cyan
$launchSw = [System.Diagnostics.Stopwatch]::StartNew()
$proc = Start-Process -FilePath $ExePath -PassThru -WindowStyle Normal
$pid_under_test = $proc.Id
$logPath = Join-Path $env:TEMP "ghostty_debug_${pid_under_test}.log"
Write-Host "[$testName]   PID=$pid_under_test  log=$logPath" -ForegroundColor DarkGray

# ----------------------------------------------------------------------
# WaitForInputIdle: measure the EXACT moment Windows considers the
# process "ready" — this is the trigger for IDC_APPSTARTING dismissal
# (the spinning cursor next to the mouse pointer). Different from the
# in-process content_ready milestone: content_ready is when initXaml
# returns; WaitForInputIdle returns when the message pump has actually
# IDLED (= called GetMessage with empty queue at least once). Anything
# the pump processes synchronously between content_ready and that first
# idle iteration extends the cursor lifetime.
# ----------------------------------------------------------------------
$inputIdleMs = $null
try {
    # Refresh process handle so we can call WaitForInputIdle.
    $proc.Refresh()
    $idleStartMs = $launchSw.Elapsed.TotalMilliseconds
    $idleResult = $proc.WaitForInputIdle($LaunchTimeoutMs)
    $idleEndMs = $launchSw.Elapsed.TotalMilliseconds
    if ($idleResult) {
        $inputIdleMs = $idleEndMs
        Write-Host "[$testName]   WaitForInputIdle returned at t=$([math]::Round($inputIdleMs,1))ms (cursor dismissed here)" -ForegroundColor DarkGray
    } else {
        Write-Host "[$testName]   WaitForInputIdle TIMED OUT after ${LaunchTimeoutMs}ms" -ForegroundColor Yellow
    }
} catch [System.InvalidOperationException] {
    # Console subsystem processes throw InvalidOperationException because
    # WaitForInputIdle is documented as GUI-only. ghostty.exe is linked
    # CONSOLE subsystem (see src/build/GhosttyExe.zig TODO) so we hit this
    # path. Fall back to "absent" for the metric.
    Write-Host "[$testName]   WaitForInputIdle not available (console subsystem) — metric skipped" -ForegroundColor Yellow
} catch {
    Write-Host "[$testName]   WaitForInputIdle error: $_" -ForegroundColor Yellow
}

# ----------------------------------------------------------------------
# Wait for content_ready
# ----------------------------------------------------------------------
function Read-LogTolerant {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return "" }
    try {
        $fs = [System.IO.FileStream]::new(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
        )
        try {
            $reader = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
            try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
        } finally { $fs.Dispose() }
    } catch {
        return ""
    }
}

$deadline = (Get-Date).AddMilliseconds($LaunchTimeoutMs)
$logContent = ""
while ((Get-Date) -lt $deadline) {
    $logContent = Read-LogTolerant -Path $logPath
    # Wait for first Present — strictly later than content_ready, captures the
    # full path through to actual frame display.
    if ($logContent -match 'PERF_INIT step="first Present"') { break }
    Start-Sleep -Milliseconds 200
}

# Always terminate the process — we only needed it long enough to capture init
try { Stop-Process -Id $pid_under_test -Force -ErrorAction SilentlyContinue } catch { }

if ($logContent -notmatch 'content_ready \(initXaml DONE\)') {
    throw "[$testName] FAIL: did not see 'content_ready' within ${LaunchTimeoutMs}ms — process crashed pre-content-ready or perf instrumentation missing"
}
if ($logContent -notmatch 'PERF_INIT step="first Present"') {
    Write-Host "[$testName] WARN: did not see 'first Present' within ${LaunchTimeoutMs}ms — D3D11 instrumentation missing or first frame did not render in time" -ForegroundColor Yellow
}

# ----------------------------------------------------------------------
# Parse PERF_INIT lines
# ----------------------------------------------------------------------
$perfLines = [regex]::Matches(
    $logContent,
    'PERF_INIT step="([^"]+)"\s+t=([\d\.]+)ms\s+d=(?:([\d\.]+)ms|-)'
) | ForEach-Object {
    [pscustomobject]@{
        Name  = $_.Groups[1].Value
        T     = [double]$_.Groups[2].Value
        D     = if ($_.Groups[3].Success) { [double]$_.Groups[3].Value } else { $null }
    }
}

if (-not $perfLines -or $perfLines.Count -eq 0) {
    throw "[$testName] FAIL: no PERF_INIT lines parsed from $logPath — instrumentation missing or log corrupted"
}

# Pseudo-steps for total lines
$appInitTotal = $null
$m = [regex]::Match($logContent, 'PERF_INIT: total App\.init = ([\d\.]+)ms')
if ($m.Success) { $appInitTotal = [double]$m.Groups[1].Value }

$contentReadyTotal = ($perfLines | Where-Object { $_.Name -eq "content_ready (initXaml DONE)" } | Select-Object -First 1).T

# ----------------------------------------------------------------------
# Report (always)
# ----------------------------------------------------------------------
Write-Host ""
Write-Host "[$testName] ============================================================" -ForegroundColor Cyan
Write-Host "[$testName] Cold-start breakdown (Debug build, ms since App.init entry)" -ForegroundColor Cyan
Write-Host "[$testName] ============================================================" -ForegroundColor Cyan
foreach ($p in $perfLines) {
    $delta = if ($null -ne $p.D) { ('d={0,7:N1}ms' -f $p.D) } else { 'd=     -  ' }
    Write-Host ("  {0,-44}  t={1,7:N1}ms  {2}" -f $p.Name, $p.T, $delta)
}
if ($appInitTotal) {
    Write-Host ("  {0,-44}  t={1,7:N1}ms" -f 'App.init total (sum)', $appInitTotal) -ForegroundColor DarkGray
}
Write-Host ("  {0,-44}  t={1,7:N1}ms" -f 'content_ready (cold-start total)', $contentReadyTotal) -ForegroundColor DarkGray
if ($null -ne $inputIdleMs) {
    $gap = $inputIdleMs - $contentReadyTotal
    $color = if ($gap -gt 500) { 'Yellow' } else { 'DarkGray' }
    Write-Host ("  {0,-44}  t={1,7:N1}ms  (gap from content_ready: {2,7:N0}ms)" -f 'WaitForInputIdle (cursor dismiss)', $inputIdleMs, $gap) -ForegroundColor $color
}
Write-Host ""

# ----------------------------------------------------------------------
# Budget enforcement
# ----------------------------------------------------------------------
$violations = @()
foreach ($k in $budgets.Keys) {
    $limit = $budgets[$k]
    $actual = $null
    if ($k -eq "App.init total") {
        $actual = $appInitTotal
    } elseif ($k -eq "content_ready total") {
        $actual = $contentReadyTotal
    } else {
        $row = $perfLines | Where-Object { $_.Name -eq $k } | Select-Object -First 1
        if ($row) { $actual = $row.T }
    }
    if ($null -eq $actual) {
        Write-Host ("  MISSING  {0,-44}  (no PERF_INIT line — instrumentation deleted?)" -f $k) -ForegroundColor Yellow
        $violations += "MISSING: $k"
        continue
    }
    if ($actual -gt $limit) {
        $over = $actual - $limit
        Write-Host ("  OVER     {0,-44}  actual={1,7:N1}ms  budget={2,5}ms  over={3,7:N1}ms" -f $k, $actual, $limit, $over) -ForegroundColor Red
        $violations += ("OVER: {0} actual={1:N1}ms budget={2}ms" -f $k, $actual, $limit)
    } else {
        $headroom = $limit - $actual
        Write-Host ("  OK       {0,-44}  actual={1,7:N1}ms  budget={2,5}ms  headroom={3,7:N1}ms" -f $k, $actual, $limit, $headroom) -ForegroundColor Green
    }
}

Write-Host ""

if ($violations.Count -eq 0) {
    Write-Host "[$testName] PASS - all $($budgets.Count) cold-start budgets met" -ForegroundColor Green
    exit 0
}

if ($BudgetReportOnly) {
    Write-Host "[$testName] BUDGET-REPORT-ONLY: $($violations.Count) budget(s) exceeded but exiting 0" -ForegroundColor Yellow
    exit 0
}

Write-Host "[$testName] FAIL - $($violations.Count) cold-start budget(s) exceeded:" -ForegroundColor Red
foreach ($v in $violations) { Write-Host "  $v" -ForegroundColor Red }
exit 1
