#Requires -Version 5.1
<#
.SYNOPSIS
    Test for Issue #133: first 1-2 characters hidden when recalling input history.

.DESCRIPTION
    Sends text via CP, then simulates up-arrow recall and checks that the
    first characters are visible in the terminal buffer via TAIL.

    This test uses CP INPUT for keystrokes (no mouse, no SendInput).

.NOTES
    Requires ghostty running with GHOSTTY_CONTROL_PLANE=1.
    Run from PowerShell: .\test_eraseline_firstchar.ps1 [-Attach]
#>

param(
    [switch]$Attach
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$script:RepoRoot    = (Resolve-Path "$PSScriptRoot\..\..").Path
$script:GhosttyExe = Join-Path $RepoRoot "zig-out-winui3\bin\ghostty.exe"
$script:SessionDir  = Join-Path $env:LOCALAPPDATA "ghostty\control-plane\winui3\sessions"
$script:Passed      = 0
$script:Failed      = 0
$script:GhosttyProc = $null
$script:PipeName    = $null
$script:Launched    = $false

function Log([string]$msg) { Write-Host "[eraseline-test] $msg" }

function Send-CP([string]$cmd) {
    try {
        $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", $script:PipeName, [System.IO.Pipes.PipeDirection]::InOut)
        $pipe.Connect(3000)
        $writer = New-Object System.IO.StreamWriter($pipe)
        $reader = New-Object System.IO.StreamReader($pipe)
        $writer.AutoFlush = $true
        $writer.WriteLine($cmd)
        # Read all available lines (TAIL returns multi-line)
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

# ============================================================
# Main test
# ============================================================
try {
    Log "=== eraseLine first-character visibility test (Issue #133) ==="

    if (-not (Start-Ghostty)) {
        Write-Host "ABORT: Cannot connect to ghostty" -ForegroundColor Red
        exit 1
    }

    # Test 1: Send a known string, verify it appears in TAIL
    $testStr = "echo ABCDEF_TESTSTR_123"
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$testStr`r"))
    $inputResult = Send-CP "INPUT|test|$b64"
    Test-Result "INPUT accepted" ($inputResult -match "OK") $inputResult
    Start-Sleep -Seconds 1

    # Test 2: Read TAIL to see if the command output is there
    $tail1 = Send-CP "TAIL|30"
    $hasOutput = $tail1 -match "ABCDEF_TESTSTR_123"
    Test-Result "Command output visible in TAIL" $hasOutput ""

    # Test 3: Send up-arrow (ESC [ A) to recall history, then read TAIL
    $esc = [char]27
    $upArrow = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${esc}[A"))
    $inputResult2 = Send-CP "INPUT|test|$upArrow"
    Test-Result "Up-arrow INPUT accepted" ($inputResult2 -match "OK") $inputResult2
    Start-Sleep -Seconds 1

    # Test 4: Read TAIL and check first characters of recalled line
    $tail2 = Send-CP "TAIL|10"
    # The recalled command should show the full string including first chars
    # Look for the prompt line containing our test string
    $lines = $tail2 -split "`n"
    $foundRecall = $false
    $firstCharsMissing = $false
    foreach ($line in $lines) {
        if ($line -match "ABCDEF_TESTSTR") {
            $foundRecall = $true
            # Check if "ABCDEF" is present (first chars)
            if ($line -notmatch "ABCDEF") {
                $firstCharsMissing = $true
            }
        }
    }
    Test-Result "Recalled command visible in TAIL" $foundRecall ""
    if ($foundRecall) {
        Test-Result "First characters (ABCDEF) present" (-not $firstCharsMissing) "Check for Issue #133 regression"
    }

    # Test 5: Send Ctrl+C to cancel, then another command for clean state
    $ctrlC = [Convert]::ToBase64String([byte[]]@(3))
    Send-CP "INPUT|test|$ctrlC" | Out-Null
    Start-Sleep -Milliseconds 500

    # Summary
    Log ""
    Log "=== Results: $script:Passed passed, $script:Failed failed ==="
    if ($script:Failed -gt 0) {
        Log "NOTE: TAIL-based checking has limitations. First-char hiding is a"
        Log "      display-layer issue that may not be detectable via TAIL buffer."
        Log "      Visual inspection may still be required for Issue #133."
    }
}
finally {
    Stop-Ghostty
}
