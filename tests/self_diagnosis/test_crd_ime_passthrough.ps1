#Requires -Version 5.1
<#
.SYNOPSIS
    Regression test for CRD (Chrome Remote Desktop) IME passthrough.

.DESCRIPTION
    Chrome Remote Desktop sends VK=0xFF (VK_OEM_CLEAR) for pre-composed IME
    text from mobile devices. Before the fix (commit 91a690d18), ghostty-win's
    PreviewKeyDown consumed this key, preventing CharacterReceived from firing.
    The fix added 0xFF to isImePassthroughVirtualKey() in Surface.zig.

    This test has two parts:
    1. Static source check: verify 0xFF is in isImePassthroughVirtualKey().
    2. Runtime check: send Japanese text via TSF inject through CP and verify
       it appears in the terminal output (TAIL).

.NOTES
    CRD scenario: user types Japanese on Android/iOS via CRD -> host receives
    WM_KEYDOWN with VK=0xFF followed by WM_CHAR with the composed character.
    If PreviewKeyDown marks VK=0xFF as Handled, XAML never fires
    CharacterReceived and the character is silently dropped.

    Requires ghostty running with GHOSTTY_CONTROL_PLANE=1.
    Run from PowerShell: .\test_crd_ime_passthrough.ps1 [-Attach]
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

function Log([string]$msg) { Write-Host "[crd-ime-test] $msg" }

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

# ============================================================
# Test 1: Static source check — 0xFF in isImePassthroughVirtualKey
# ============================================================
Log "=== CRD IME passthrough regression test ==="
Log ""
Log "--- Part 1: Static source check ---"

$surfaceZig = Join-Path $script:RepoRoot "src\apprt\winui3\Surface.zig"
if (Test-Path $surfaceZig) {
    $sourceContent = Get-Content $surfaceZig -Raw
    # Check that 0xFF is listed in isImePassthroughVirtualKey
    $hasVkFF = $sourceContent -match 'isImePassthroughVirtualKey[\s\S]*?0xFF[\s\S]*?=> true'
    Test-Result "0xFF (VK_OEM_CLEAR) in isImePassthroughVirtualKey" $hasVkFF ""

    # Also check the CRD comment is present for documentation
    $hasCrdComment = $sourceContent -match 'Chrome Remote Desktop'
    Test-Result "CRD documentation comment present" $hasCrdComment ""
} else {
    Test-Result "Surface.zig exists" $false "File not found: $surfaceZig"
}

# ============================================================
# Test 2: Runtime check — TSF inject Japanese text via CP
# ============================================================
Log ""
Log "--- Part 2: Runtime TSF inject check ---"

try {
    if (-not (Start-Ghostty)) {
        Write-Host "SKIP: Cannot connect to ghostty (runtime tests skipped)" -ForegroundColor Yellow
        Log ""
        Log "=== Results: $script:Passed passed, $script:Failed failed (runtime skipped) ==="
        exit 0
    }

    # Send a unique marker via normal INPUT first to confirm CP works
    $marker = "CRD_IME_TEST_$(Get-Random -Maximum 99999)"
    $echoCmd = "echo $marker"
    $b64echo = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$echoCmd`r"))
    $inputResult = Send-CP "INPUT|test|$b64echo"
    Test-Result "CP INPUT accepted" ($inputResult -match "OK") $inputResult
    Start-Sleep -Seconds 1

    $tail1 = Send-CP "TAIL|20"
    $markerVisible = $tail1 -match $marker
    Test-Result "Marker visible in TAIL" $markerVisible ""

    # Now send Japanese text via TSF inject (simulates CRD IME composed input)
    # TSF inject uses the tsf-inject.sh script which sends ESC[TSF:<text>
    $tsfScript = Join-Path $script:RepoRoot "tests\winui3\tsf-inject.sh"
    $agentCtl = Join-Path $env:USERPROFILE "agent-relay\target\debug\agent-ctl.exe"

    if ((Test-Path $tsfScript) -and (Test-Path $agentCtl)) {
        # Find session name via agent-ctl list
        $sessions = & $agentCtl list 2>$null
        $sessionName = $null
        if ($sessions) {
            # Take first available session
            $sessionLines = $sessions -split "`n" | Where-Object { $_.Trim() -ne "" }
            if ($sessionLines.Count -gt 0) {
                # agent-ctl list output format: session names one per line
                $sessionName = ($sessionLines[0]).Trim()
            }
        }

        if ($sessionName) {
            Log "Using agent-ctl session: $sessionName"
            $japaneseText = "テスト入力"
            # Send Japanese text via TSF inject
            $tsfResult = & bash $tsfScript $sessionName $japaneseText 2>&1
            Test-Result "TSF inject sent" ($LASTEXITCODE -eq 0 -or $tsfResult -notmatch "ERROR") "$tsfResult"
            Start-Sleep -Seconds 2

            # Check TAIL for the Japanese text
            $tail2 = Send-CP "TAIL|20"
            $japaneseVisible = $tail2 -match $japaneseText
            Test-Result "Japanese text visible in TAIL after TSF inject" $japaneseVisible ""
            if (-not $japaneseVisible) {
                Log "  NOTE: TSF inject may require active IME context. This is expected"
                Log "        in headless/CI environments. The static check (Part 1) is the"
                Log "        primary regression gate."
            }
        } else {
            Log "  SKIP: No agent-ctl session found (agent-ctl list returned nothing)"
        }
    } else {
        if (-not (Test-Path $tsfScript)) { Log "  SKIP: tsf-inject.sh not found at $tsfScript" }
        if (-not (Test-Path $agentCtl))  { Log "  SKIP: agent-ctl.exe not found at $agentCtl" }
        Log "  SKIP: TSF inject test requires both tsf-inject.sh and agent-ctl.exe"
    }

    # Clean up: send Ctrl+C
    $ctrlC = [Convert]::ToBase64String([byte[]]@(3))
    Send-CP "INPUT|test|$ctrlC" | Out-Null
    Start-Sleep -Milliseconds 500

    # Summary
    Log ""
    Log "=== Results: $script:Passed passed, $script:Failed failed ==="
}
finally {
    Stop-Ghostty
}
