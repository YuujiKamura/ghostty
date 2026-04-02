#Requires -Version 5.1
<#
.SYNOPSIS
    Regression test for text selection fix (Issue #132).

.DESCRIPTION
    Issue #132: Text selection broke in XAML Islands because Win32 SetCapture/
    ReleaseCapture do not work inside XAML-hosted HWNDs. The fix replaced them
    with XAML CapturePointer/ReleasePointerCapture on the surface_grid UIElement.

    This test has three parts:
    1. Static check: Surface.zig uses CapturePointer (XAML), not SetCapture (Win32).
    2. Static check: com_native.zig has the Pointer() helper for IPointerRoutedEventArgs.
    3. Runtime check: launch ghostty, verify no CapturePointer errors in debug log.

.NOTES
    Requires ghostty running with GHOSTTY_CONTROL_PLANE=1.
    Run from PowerShell: .\test_text_selection.ps1 [-Attach]
#>

param(
    [switch]$Attach
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$script:RepoRoot    = (Resolve-Path "$PSScriptRoot\..\..").Path
$script:GhosttyExe  = Join-Path $RepoRoot "zig-out-winui3\bin\ghostty.exe"
$script:SessionDir   = Join-Path $env:LOCALAPPDATA "ghostty\control-plane\winui3\sessions"
$script:Passed       = 0
$script:Failed       = 0
$script:Skipped      = 0
$script:GhosttyProc  = $null
$script:PipeName     = $null
$script:Launched     = $false

function Log([string]$msg) { Write-Host "[text-sel-test] $msg" }

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

function Find-Session {
    if (-not (Test-Path $script:SessionDir)) { return $false }
    $sessions = Get-ChildItem $script:SessionDir -Filter "*.json" -ErrorAction SilentlyContinue
    foreach ($s in $sessions) {
        $json = Get-Content $s.FullName -Raw | ConvertFrom-Json
        $script:PipeName = $json.pipe_name
        if (-not $script:PipeName) { $script:PipeName = $json.pipeName }
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
            return $true
        }
        Log "FAIL: -Attach specified but no running ghostty found"
        return $false
    }

    $env:GHOSTTY_CONTROL_PLANE = "1"
    $script:GhosttyProc = Start-Process -FilePath $script:GhosttyExe -PassThru -ErrorAction SilentlyContinue
    if (-not $script:GhosttyProc) {
        Log "FAIL: Could not start ghostty"
        return $false
    }
    $script:Launched = $true
    Start-Sleep -Seconds 3

    for ($i = 0; $i -lt 10; $i++) {
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

function Test-Result([string]$name, [bool]$pass, [string]$detail = "") {
    if ($pass) {
        $script:Passed++
        Write-Host "  PASS: $name $detail" -ForegroundColor Green
    } else {
        $script:Failed++
        Write-Host "  FAIL: $name $detail" -ForegroundColor Red
    }
}

function Test-Skip([string]$name, [string]$detail = "") {
    $script:Skipped++
    Write-Host "  SKIP: $name $detail" -ForegroundColor Yellow
}

# ============================================================
# Part 1: Static check — Surface.zig uses XAML CapturePointer
# ============================================================
Log "=== Text selection regression test (Issue #132) ==="
Log ""
Log "--- Part 1: Static source check (Surface.zig) ---"

$surfaceZig = Join-Path $script:RepoRoot "src\apprt\winui3\Surface.zig"
if (Test-Path $surfaceZig) {
    $src = Get-Content $surfaceZig -Raw

    # CapturePointer (XAML) must be present
    $hasCapturePointer = $src -match 'CapturePointer'
    Test-Result "Surface.zig uses XAML CapturePointer" $hasCapturePointer

    # ReleasePointerCapture (XAML) must be present
    $hasReleasePointerCapture = $src -match 'ReleasePointerCapture'
    Test-Result "Surface.zig uses XAML ReleasePointerCapture" $hasReleasePointerCapture

    # Win32 SetCapture must NOT be called (removed by fix)
    $callsSetCapture = $src -match 'os\.SetCapture\(' -or $src -match 'win32\.SetCapture\('
    Test-Result "Surface.zig does NOT call Win32 SetCapture" (-not $callsSetCapture)

    # Win32 ReleaseCapture must NOT be called (removed by fix)
    $callsReleaseCapture = $src -match 'os\.ReleaseCapture\(\)' -or $src -match 'win32\.ReleaseCapture\(\)'
    Test-Result "Surface.zig does NOT call Win32 ReleaseCapture" (-not $callsReleaseCapture)
} else {
    Test-Result "Surface.zig exists" $false "File not found: $surfaceZig"
}

# ============================================================
# Part 2: Static check — com_native.zig has Pointer() helper
# ============================================================
Log ""
Log "--- Part 2: Static source check (com_native.zig) ---"

$comNativeZig = Join-Path $script:RepoRoot "src\apprt\winui3\com_native.zig"
if (Test-Path $comNativeZig) {
    $src = Get-Content $comNativeZig -Raw

    # Pointer() helper on IPointerRoutedEventArgs
    $hasPointerHelper = $src -match 'pub fn Pointer\(self'
    Test-Result "com_native.zig has Pointer() helper" $hasPointerHelper

    # IPointerRoutedEventArgs struct
    $hasEventArgs = $src -match 'IPointerRoutedEventArgs'
    Test-Result "com_native.zig defines IPointerRoutedEventArgs" $hasEventArgs
} else {
    Test-Result "com_native.zig exists" $false "File not found: $comNativeZig"
}

# ============================================================
# Part 3: Runtime check — CapturePointer error in log
# ============================================================
Log ""
Log "--- Part 3: Runtime check (CapturePointer log) ---"

try {
    if (-not (Start-Ghostty)) {
        Test-Skip "Runtime CapturePointer check" "(cannot connect to ghostty)"
        Log ""
        Log "=== Results: $script:Passed passed, $script:Failed failed, $script:Skipped skipped ==="
        exit 0
    }

    # Send a click-like interaction: type something then check log for errors
    $marker = "SEL_TEST_$(Get-Random -Maximum 99999)"
    $echoCmd = "echo $marker"
    $b64echo = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$echoCmd`r"))
    $inputCmd = 'INPUT|test|' + $b64echo
    $inputResult = Send-CP $inputCmd
    Test-Result "CP INPUT accepted" ($inputResult -match "OK") $inputResult
    Start-Sleep -Seconds 1

    # Check TAIL for the marker (confirms ghostty is responsive)
    $tail = Send-CP 'TAIL|20'
    $markerVisible = $tail -match $marker
    Test-Result "Ghostty responsive (marker in TAIL)" $markerVisible

    # Check debug log for CapturePointer errors
    $logPath = Join-Path $env:LOCALAPPDATA "ghostty\ghostty.log"
    if (Test-Path $logPath) {
        $logContent = Get-Content $logPath -Tail 200 -ErrorAction SilentlyContinue
        $captureErrors = $logContent | Where-Object { $_ -match 'CapturePointer failed' }
        $hasNoErrors = ($captureErrors.Count -eq 0)
        Test-Result "No CapturePointer errors in log" $hasNoErrors "($($captureErrors.Count) errors found)"
    } else {
        Test-Skip "CapturePointer log check" "(log file not found at $logPath)"
    }

    Log ""
    Log "=== Results: $script:Passed passed, $script:Failed failed, $script:Skipped skipped ==="
}
finally {
    Stop-Ghostty
}
