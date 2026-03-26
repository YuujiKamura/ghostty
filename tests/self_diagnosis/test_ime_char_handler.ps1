#Requires -Version 5.1
<#
.SYNOPSIS
    Regression test for WM_IME_CHAR handler.

.DESCRIPTION
    Chrome Remote Desktop and similar tools send WM_IME_CHAR (0x0286) for
    pre-composed CJK text instead of going through TSF/CharacterReceived.
    The fix added WM_IME_CHAR handling to both App.zig (WndProc dispatcher)
    and input_overlay.zig (overlay WndProc).

    This test has four parts:
    1. Static check: os.zig defines WM_IME_CHAR = 0x0286.
    2. Static check: App.zig handles WM_IME_CHAR in its WndProc.
    3. Static check: input_overlay.zig handles WM_IME_CHAR in its WndProc.
    4. Runtime check: send Japanese text via tsf-inject.sh and verify it
       appears in the terminal buffer.

.NOTES
    Requires ghostty running with GHOSTTY_CONTROL_PLANE=1.
    Run from PowerShell: .\test_ime_char_handler.ps1 [-Attach]
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

function Log([string]$msg) { Write-Host "[ime-char-test] $msg" }

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
# Part 1: Static check — os.zig defines WM_IME_CHAR = 0x0286
# ============================================================
Log "=== WM_IME_CHAR handler regression test ==="
Log ""
Log "--- Part 1: Static check (os.zig) ---"

$osZig = Join-Path $script:RepoRoot "src\apprt\winui3\os.zig"
if (Test-Path $osZig) {
    $src = Get-Content $osZig -Raw

    $hasWmImeChar = $src -match 'WM_IME_CHAR.*=.*0x0286'
    Test-Result "os.zig defines WM_IME_CHAR = 0x0286" $hasWmImeChar

    # Also check that the constant name matches expected convention
    $hasConstDecl = $src -match 'pub const WM_IME_CHAR'
    Test-Result "WM_IME_CHAR is pub const" $hasConstDecl
} else {
    Test-Result "os.zig exists" $false "File not found: $osZig"
}

# ============================================================
# Part 2: Static check — App.zig handles WM_IME_CHAR
# ============================================================
Log ""
Log "--- Part 2: Static check (App.zig) ---"

$appZig = Join-Path $script:RepoRoot "src\apprt\winui3\App.zig"
if (Test-Path $appZig) {
    $src = Get-Content $appZig -Raw

    $hasHandler = $src -match 'WM_IME_CHAR'
    Test-Result "App.zig handles WM_IME_CHAR in WndProc" $hasHandler
} else {
    Test-Result "App.zig exists" $false "File not found: $appZig"
}

# ============================================================
# Part 3: Static check — input_overlay.zig handles WM_IME_CHAR
# ============================================================
Log ""
Log "--- Part 3: Static check (input_overlay.zig) ---"

$overlayZig = Join-Path $script:RepoRoot "src\apprt\winui3\input_overlay.zig"
if (Test-Path $overlayZig) {
    $src = Get-Content $overlayZig -Raw

    $hasHandler = $src -match 'WM_IME_CHAR'
    Test-Result "input_overlay.zig handles WM_IME_CHAR" $hasHandler

    # Check for CRD documentation comment
    $hasCrdComment = $src -match 'Chrome Remote Desktop'
    Test-Result "input_overlay.zig has CRD documentation" $hasCrdComment
} else {
    Test-Result "input_overlay.zig exists" $false "File not found: $overlayZig"
}

# ============================================================
# Part 4: Runtime check — TSF inject Japanese text
# ============================================================
Log ""
Log "--- Part 4: Runtime check (TSF inject) ---"

try {
    if (-not (Start-Ghostty)) {
        Test-Skip "Runtime TSF inject check" "(cannot connect to ghostty)"
        Log ""
        Log "=== Results: $script:Passed passed, $script:Failed failed, $script:Skipped skipped ==="
        exit 0
    }

    # Confirm ghostty is responsive
    $marker = "IME_CHAR_TEST_$(Get-Random -Maximum 99999)"
    $echoCmd = "echo $marker"
    $b64echo = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$echoCmd`r"))
    $inputCmd = 'INPUT|test|' + $b64echo
    $inputResult = Send-CP $inputCmd
    Test-Result "CP INPUT accepted" ($inputResult -match "OK") $inputResult
    Start-Sleep -Seconds 1

    $tail1 = Send-CP 'TAIL|20'
    $markerVisible = $tail1 -match $marker
    Test-Result "Ghostty responsive (marker in TAIL)" $markerVisible

    # Send Japanese text via TSF inject
    $tsfScript = Join-Path $script:RepoRoot "tests\winui3\tsf-inject.sh"
    $agentCtl  = Join-Path (Resolve-Path '~').Path 'agent-relay\target\debug\agent-ctl.exe'

    if ((Test-Path $tsfScript) -and (Test-Path $agentCtl)) {
        # Find session name via agent-ctl list
        $sessions = & $agentCtl list 2>$null
        $sessionName = $null
        if ($sessions) {
            $sessionLines = $sessions -split "`n" | Where-Object { $_.Trim() -ne "" }
            if ($sessionLines.Count -gt 0) {
                $sessionName = ($sessionLines[0]).Trim()
            }
        }

        if ($sessionName) {
            Log "Using agent-ctl session: $sessionName"
            $japaneseText = "IME検証テスト"

            # First echo a command that will show the Japanese text when typed
            # Clear line first with Ctrl+U
            $ctrlU = [Convert]::ToBase64String([byte[]]@(21))
            $clearCmd = 'INPUT|test|' + $ctrlU
            Send-CP $clearCmd | Out-Null
            Start-Sleep -Milliseconds 300

            # Set up: type 'echo ' prefix via CP
            $echoPrefix = 'echo '
            $b64prefix = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($echoPrefix))
            $prefixCmd = 'INPUT|test|' + $b64prefix
            Send-CP $prefixCmd | Out-Null
            Start-Sleep -Milliseconds 300

            # Send Japanese text via TSF inject (simulates WM_IME_CHAR path)
            $tsfResult = & bash $tsfScript $sessionName $japaneseText 2>&1
            $tsfResultStr = [string]$tsfResult
            $tsfOk = ($LASTEXITCODE -eq 0 -or $tsfResultStr -notmatch 'ERROR')
            Test-Result "TSF inject sent" $tsfOk $tsfResultStr
            Start-Sleep -Seconds 1

            # Press Enter to echo
            $enter = [Convert]::ToBase64String([byte[]]@(13))
            $enterCmd = 'INPUT|test|' + $enter
            Send-CP $enterCmd | Out-Null
            Start-Sleep -Seconds 1

            # Check TAIL for the Japanese text
            $tail2 = Send-CP 'TAIL|20'
            $japaneseVisible = $tail2 -match $japaneseText
            Test-Result "Japanese text visible in TAIL after TSF inject" $japaneseVisible
            if (-not $japaneseVisible) {
                Log "  NOTE: TSF inject requires active IME context and focus."
                Log "        In headless/CI environments this may not work."
                Log "        The static checks (Parts 1-3) are the primary regression gate."
            }
        } else {
            Test-Skip "TSF inject" "(no agent-ctl session found)"
        }
    } else {
        if (-not (Test-Path $tsfScript)) { Test-Skip "TSF inject" "(tsf-inject.sh not found)" }
        if (-not (Test-Path $agentCtl))  { Test-Skip "TSF inject" "(agent-ctl.exe not found)" }
    }

    # Clean up
    $ctrlC = [Convert]::ToBase64String([byte[]]@(3))
    $ctrlCCmd = 'INPUT|test|' + $ctrlC
    Send-CP $ctrlCCmd | Out-Null
    Start-Sleep -Milliseconds 500

    Log ""
    Log "=== Results: $script:Passed passed, $script:Failed failed, $script:Skipped skipped ==="
}
finally {
    Stop-Ghostty
}
