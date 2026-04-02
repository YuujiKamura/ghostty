#Requires -Version 5.1
<#
.SYNOPSIS
    Automated cursor movement test via CP INPUT/TAIL.

.DESCRIPTION
    Sends cursor movement ESC sequences via CP INPUT, then verifies
    cursor position by writing marker characters and reading TAIL.

    Tests:
    1. CUP (ESC[row;colH) - absolute cursor positioning
    2. CUU/CUD/CUF/CUB - relative cursor movement
    3. Cursor position after writing text

.NOTES
    Requires ghostty running with GHOSTTY_CONTROL_PLANE=1.
    Run: .\cursor_test.ps1 [-Attach]
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
$script:GhosttyProc  = $null
$script:PipeName     = $null
$script:Launched     = $false

function Log([string]$msg) { Write-Host "[cursor-test] $msg" }

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

function Send-Input([string]$text) {
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text))
    return Send-CP "INPUT|test|$b64"
}

function Send-Esc([string]$seq) {
    $esc = [char]27
    return Send-Input "${esc}${seq}"
}

function Get-Tail([int]$lines = 30) {
    return Send-CP "TAIL|$lines"
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
    Log "=== Cursor movement verification via CP INPUT/TAIL ==="

    if (-not (Start-Ghostty)) {
        Write-Host "ABORT: Cannot connect to ghostty" -ForegroundColor Red
        exit 1
    }

    $esc = [char]27

    # ----------------------------------------------------------
    # Test 1: Write a line, verify it appears in TAIL
    # ----------------------------------------------------------
    # Use echo command to print known text (shell interprets it)
    Send-Input "echo CURSOR_LINE1_ABCDEFGHIJ`r" | Out-Null
    Start-Sleep -Seconds 1

    $tail = Get-Tail 15
    Test-Result "Line1 visible in TAIL" ($tail -match "CURSOR_LINE1_ABCDEFGHIJ") "sent echo, checking TAIL"

    # ----------------------------------------------------------
    # Test 2: CUP absolute positioning - move to row 1 col 5
    #   then write a marker. Use raw ESC sequences via cat/printf.
    #   Strategy: printf lines then overwrite with CUP + marker.
    # ----------------------------------------------------------
    # Print two known lines, then use CUP to overwrite a character
    $seq = "printf 'ROW1_12345\nROW2_ABCDE\n${esc}[1;6HMARK1'`r"
    Send-Input $seq | Out-Null
    Start-Sleep -Seconds 1

    $tail = Get-Tail 15
    # After CUP to row 1, col 6 and writing "MARK1",
    # ROW1 should have "MARK1" starting at position 6 (overwriting "12345" partially)
    # The line should read "ROW1_MARK1" (5 chars of ROW1_ + MARK1 at col 6)
    Test-Result "CUP positioned marker visible" ($tail -match "ROW1_MARK1") "CUP ESC[1;6H then write MARK1"

    # ----------------------------------------------------------
    # Test 3: Relative cursor movement - CUU (up), CUF (forward)
    #   Print two lines, move up 1, forward 3, write marker
    # ----------------------------------------------------------
    $seq2 = "printf 'AAA_BBB_CCC\nDDD_EEE_FFF\n${esc}[1A${esc}[4CXYZ'`r"
    Send-Input $seq2 | Out-Null
    Start-Sleep -Seconds 1

    $tail = Get-Tail 15
    # CUU(1) goes up to AAA_BBB_CCC line, CUF(4) moves right 4 from col 1
    # Writing "XYZ" at col 5 of first line: "AAA_XYZ_CCC" (overwriting "BBB")
    # But we're on the DDD line start, so CUU goes to DDD line start? No -
    # after printf, cursor is at start of new line. CUU(1) goes to start of "DDD_EEE_FFF".
    # CUF(4) moves to col 5. Writing XYZ overwrites EEE -> "DDD_XYZ_FFF"
    Test-Result "Relative cursor (CUU+CUF) marker visible" ($tail -match "DDD_XYZ") "CUU(1)+CUF(4) then write XYZ"

    # ----------------------------------------------------------
    # Test 4: CUB (cursor back) - write text then move back
    # ----------------------------------------------------------
    $seq3 = "printf 'HELLO_WORLD${esc}[5D!!!'`r"
    Send-Input $seq3 | Out-Null
    Start-Sleep -Seconds 1

    $tail = Get-Tail 15
    # HELLO_WORLD has 11 chars, CUB(5) goes back 5 from end to pos 7,
    # writing "!!!" overwrites "ORLD" partially -> "HELLO_!!!LD"
    Test-Result "CUB cursor back marker visible" ($tail -match "HELLO_!!!") "CUB(5) then write !!!"

    # ----------------------------------------------------------
    # Test 5: Verify original cursor_test content works via printf
    # ----------------------------------------------------------
    $seq4 = "printf 'ABCDEFGHIJ\nKLMNOPQRST\n${esc}[2A${esc}[4G*'`r"
    Send-Input $seq4 | Out-Null
    Start-Sleep -Seconds 1

    $tail = Get-Tail 15
    # CUU(2) goes up 2 lines to ABCDEFGHIJ, CUG(4) sets column to 4
    # Writing "*" at col 4 overwrites D -> "ABC*EFGHIJ"
    Test-Result "Original cursor_test pattern (overwrite D with *)" ($tail -match "ABC\*EFGHIJ") "CUU(2)+CHA(4) then write *"

    # ----------------------------------------------------------
    # Cleanup: Ctrl+C
    # ----------------------------------------------------------
    Send-Input ([string][char]3) | Out-Null
    Start-Sleep -Milliseconds 500

    # Summary
    Log ""
    Log "=== Results: $script:Passed passed, $script:Failed failed ==="
    if ($script:Failed -gt 0) { exit 1 }
}
finally {
    Stop-Ghostty
}
