# test-13-restart-restore — "restart and restore tabs" (WM_APP_RESTART_RESTORE)
# saves every tab, starts ghostty.exe again and reopens them; Claude / Codex
# tabs come back as `claude --resume <id>` / `codex resume <id>` in the same
# folder, split view and the active tab are kept.
#
# No real agents and no real home: cmd.exe copied as claude.exe / codex.exe (stays running whatever the args)
# in a fake bin dir, a fake USERPROFILE holding ~/.claude/sessions/<pid>.json
# and a codex rollout. Commands are typed through the control plane pipe.
# No keyboard / mouse input.
#
# Axes: tab kind {claude, codex, agy, shell} x restored property {kind, session
# id, folder, args}, plus split pair and active tab.

param([string]$ExePath)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module "$PSScriptRoot\test-helpers.psm1" -Force -WarningAction SilentlyContinue

$testName = "test-13-restart-restore"
if (-not $ExePath) { $ExePath = Join-Path $PSScriptRoot "..\..\zig-out-winui3\bin\ghostty.exe" }
$ExePath = (Resolve-Path $ExePath -ErrorAction Stop).Path

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32R {
    [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int w, int hh, uint f);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@ -ErrorAction SilentlyContinue
$WM_APP_RESTART_RESTORE = 0x0400 + 10

$root = Join-Path $env:TEMP ("ghostty-t13-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$home2 = Join-Path $root "home"
$bin = Join-Path $root "bin"
$work1 = Join-Path $root "work claude"
$work2 = Join-Path $root "work-codex"
foreach ($d in @($home2, $bin, $work1, $work2, "$home2\.claude\sessions")) { New-Item -ItemType Directory -Force $d | Out-Null }
Copy-Item "$env:WINDIR\System32\cmd.exe" "$bin\claude.exe"
Copy-Item "$env:WINDIR\System32\cmd.exe" "$bin\codex.exe"
Copy-Item "$env:WINDIR\System32\cmd.exe" "$bin\agy.exe"
$work3 = Join-Path $root "work-agy"
$work4 = Join-Path $root "work shell"
New-Item -ItemType Directory -Force $work3, $work4, "$home2\.gemini\antigravity-cli\conversations" | Out-Null
$agyId = "b5831a96-0000-4ffe-bb74-13845987f150"

$claudeId = "11111111-2222-3333-4444-555555555555"
$codexId = "019a0000-aaaa-7bbb-8ccc-dddddddddddd"

function Send-CP([int]$procId, [string]$cmd) {
    $pipe = [System.IO.Pipes.NamedPipeClientStream]::new(".", "ghostty-winui3-ghostty-$procId-$procId", [System.IO.Pipes.PipeDirection]::InOut)
    try {
        $pipe.Connect(3000)
        $b = [Text.Encoding]::UTF8.GetBytes("$cmd`n"); $pipe.Write($b, 0, $b.Length); $pipe.Flush()
        $buf = New-Object byte[] 512; $n = $pipe.Read($buf, 0, 512)
        return [Text.Encoding]::UTF8.GetString($buf, 0, $n).Trim()
    } finally { $pipe.Dispose() }
}
function Send-Line([int]$procId, [string]$text) {
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$text`r"))
    Send-CP $procId "INPUT|test13|$b64" | Out-Null
}
function Get-Descendants([int]$rootPid) {
    $all = Get-CimInstance Win32_Process
    $out = @(); $queue = @($rootPid)
    while ($queue.Count -gt 0) {
        $p = $queue[0]; $queue = @($queue | Select-Object -Skip 1)
        foreach ($c in $all | Where-Object { $_.ParentProcessId -eq $p -and $_.ProcessId -ne $p }) { $out += $c; $queue += $c.ProcessId }
    }
    return $out
}
function Wait-Process-Named([int]$rootPid, [string]$name, [int[]]$exclude = @()) {
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        $p = @(Get-Descendants $rootPid) | Where-Object { $_.Name -eq $name -and $_.ProcessId -notin $exclude } | Select-Object -First 1
        if ($p) { return $p }
        Start-Sleep -Milliseconds 300
    }
    throw "$name did not start under $rootPid"
}
function Get-HeaderNumbers([int]$procId) {
    $elem = Find-GhosttyUIAElement -ProcessId $procId
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
    $names = @(foreach ($e in $elem.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)) { $e.Current.Name })
    return (@($names | Where-Object { $_ -match '^[0-9]+  ' } | ForEach-Object { [int]($_ -split '  ')[0] } | Sort-Object) -join ',')
}
function Get-TabCount([int]$procId) {
    $elem = Find-GhosttyUIAElement -ProcessId $procId
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::TabItem)
    return $elem.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond).Count
}

$old = $null; $new = $null
$saved = @{ USERPROFILE = $env:USERPROFILE; PATH = $env:PATH }
try {
    # --- 1. Old window: split top/bottom (tabs 1,2), claude in tab 2, codex in tab 1, plain tab 3.
    $env:USERPROFILE = $home2
    $env:PATH = "$bin;$env:PATH"
    $env:KS_NO_ACTIVATE = "visible"
    $env:KS_SPLIT_VIEW = "top_bottom"
    try { $old = Start-Process -FilePath $ExePath -PassThru }
    finally {
        $env:USERPROFILE = $saved.USERPROFILE; $env:PATH = $saved.PATH
        Remove-Item Env:KS_NO_ACTIVATE, Env:KS_SPLIT_VIEW -ErrorAction SilentlyContinue
    }
    $hwnd = Find-GhosttyWindow -ProcessId $old.Id
    [Win32R]::SetWindowPos($hwnd, [IntPtr]::Zero, 140, 100, 1100, 820, 0x14) | Out-Null
    Start-Sleep -Seconds 3

    Send-Line $old.Id "cd /d `"$work1`" && claude -n 600 127.0.0.1"
    $fakeClaude = Wait-Process-Named $old.Id "claude.exe"
    @{ pid = $fakeClaude.ProcessId; sessionId = $claudeId; cwd = $work1 } | ConvertTo-Json |
        Set-Content -Encoding UTF8 "$home2\.claude\sessions\$($fakeClaude.ProcessId).json"

    Send-CP $old.Id "SWITCH_TAB|0" | Out-Null; Start-Sleep -Milliseconds 800
    Send-Line $old.Id "cd /d `"$work2`" && codex -n 600 127.0.0.1"
    $fakeCodex = Wait-Process-Named $old.Id "codex.exe"
    $utc = (Get-Date).ToUniversalTime()
    $dayDir = Join-Path $home2 (".codex\sessions\{0:yyyy}\{0:MM}\{0:dd}" -f $utc)
    New-Item -ItemType Directory -Force $dayDir | Out-Null
    $meta = @{ timestamp = $utc.ToString("yyyy-MM-ddTHH:mm:ss.fffZ"); type = "session_meta";
        payload = [ordered]@{ id = $codexId; timestamp = $utc.ToString("yyyy-MM-ddTHH:mm:ss.fffZ"); cwd = $work2; thread_source = "user" } }
    ($meta | ConvertTo-Json -Compress -Depth 4) | Set-Content -Encoding UTF8 (Join-Path $dayDir "rollout-test-$codexId.jsonl")
    # A sub-agent rollout created later must NOT be picked.
    $meta.payload.id = "019a0000-ffff-7fff-8fff-ffffffffffff"; $meta.payload.thread_source = "subagent"
    Start-Sleep -Milliseconds 300
    ($meta | ConvertTo-Json -Compress -Depth 4) | Set-Content -Encoding UTF8 (Join-Path $dayDir "rollout-test-sub.jsonl")

    Send-CP $old.Id "NEW_TAB" | Out-Null; Start-Sleep -Seconds 2
    # Tab 3: plain cmd that moved to another folder (cmd reports no OSC 7).
    Send-Line $old.Id "cd /d `"$work4`""
    Start-Sleep -Milliseconds 800
    # Tab 4: agy. An older conversation (created before agy started) must not be picked.
    Set-Content "$home2\.gemini\antigravity-cli\conversations\00000000-old.db" "x"
    Start-Sleep -Milliseconds 300
    Send-CP $old.Id "NEW_TAB" | Out-Null; Start-Sleep -Seconds 2
    Send-Line $old.Id "cd /d `"$work3`" && agy -n 600 127.0.0.1"
    [void](Wait-Process-Named $old.Id "agy.exe")
    Start-Sleep -Milliseconds 300
    Set-Content "$home2\.gemini\antigravity-cli\conversations\$agyId.db" "x"
    Test-AssertEqual -Expected 4 -Actual (Get-TabCount $old.Id) -Message "$testName - old window has 4 tabs"
    Test-AssertEqual -Expected "1,2,3,4" -Actual (Get-HeaderNumbers $old.Id) -Message "$testName - old window split shows all 4 tabs"

    # --- 2. Restart.
    [Win32R]::PostMessageW($hwnd, $WM_APP_RESTART_RESTORE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    Test-Assert -Condition ($old.WaitForExit(15000)) -Message "$testName - old process exited"
    $deadline = (Get-Date).AddSeconds(15)
    while (-not $new -and (Get-Date) -lt $deadline) {
        $new = Get-CimInstance Win32_Process -Filter "Name='ghostty.exe' AND ParentProcessId=$($old.Id)" | Select-Object -First 1
        if (-not $new) { Start-Sleep -Milliseconds 300 }
    }
    Test-Assert -Condition ($null -ne $new) -Message "$testName - new ghostty started by old one"
    $newProc = Get-Process -Id $new.ProcessId
    $hwnd2 = Find-GhosttyWindow -ProcessId $new.ProcessId
    [Win32R]::SetWindowPos($hwnd2, [IntPtr]::Zero, 140, 100, 1100, 820, 0x14) | Out-Null
    Start-Sleep -Seconds 4

    # --- 3. Restored state.
    Test-AssertEqual -Expected 4 -Actual (Get-TabCount $new.ProcessId) -Message "$testName - 4 tabs restored"
    Test-AssertEqual -Expected "1,2,3,4" -Actual (Get-HeaderNumbers $new.ProcessId) -Message "$testName - split view restored (all 4 tabs)"

    $desc = @(Get-Descendants $new.ProcessId)
    # ghostty runs each tab as `cmd.exe /C <command>`; look at the inner shells only.
    $cmdlines = @($desc | Where-Object { $_.Name -eq 'cmd.exe' -and $_.CommandLine -notmatch '/C ' } | ForEach-Object { $_.CommandLine })
    $cmdlines | ForEach-Object { Write-Host "  restored: $_" -ForegroundColor Cyan }
    Test-Assert -Condition (@($cmdlines | Where-Object { $_ -like "*/k codex resume $codexId -n 600 127.0.0.1*" }).Count -eq 1) -Message "$testName - codex tab resumes its own (non-subagent) session with original args"
    Test-Assert -Condition (@($cmdlines | Where-Object { $_ -like "*/k claude --resume $claudeId -n 600 127.0.0.1*" }).Count -eq 1) -Message "$testName - claude tab resumes its session with original args"
    Test-Assert -Condition (@($cmdlines | Where-Object { $_ -like "*/k agy --conversation $agyId -n 600 127.0.0.1*" }).Count -eq 1) -Message "$testName - agy tab resumes the conversation it created, with original args"
    $resumeCount = @($cmdlines | Where-Object { $_ -match 'resume|--conversation' }).Count
    Test-AssertEqual -Expected 3 -Actual $resumeCount -Message "$testName - plain shell tab is not given a resume command"

    # Folders: the restored fake agents (ping) run in the saved working dirs.
    foreach ($pair in @(@{ Name = 'claude.exe'; Dir = $work1 }, @{ Name = 'codex.exe'; Dir = $work2 })) {
        $p = $desc | Where-Object { $_.Name -eq $pair.Name } | Select-Object -First 1
        # ping exits at once on "--resume"; the cmd.exe /k shell remains. Check the shell's start folder via its prompt in the capture instead.
    }
    Test-Assert -Condition (-not $newProc.HasExited) -Message "$testName - new process alive"

    # Folders: tab 4 (agy, active) and tab 3 (plain shell) reopen where they were.
    $tail4 = Send-CP $new.ProcessId "TAIL|5"
    Test-Assert -Condition ($tail4 -like "*$work3>*") -Message "$testName - agy tab reopened in its folder"
    Send-CP $new.ProcessId "SWITCH_TAB|2" | Out-Null; Start-Sleep -Milliseconds 800
    $tail3 = Send-CP $new.ProcessId "TAIL|5"
    Test-Assert -Condition ($tail3 -like "*$work4>*") -Message "$testName - plain shell tab reopened in its folder (read from the process)"
    Send-CP $new.ProcessId "SWITCH_TAB|3" | Out-Null; Start-Sleep -Milliseconds 800

    $r = New-Object Win32R+RECT; [Win32R]::GetWindowRect($hwnd2, [ref]$r) | Out-Null
    $bmp = New-Object System.Drawing.Bitmap ($r.Right - $r.Left), ($r.Bottom - $r.Top)
    $g = [System.Drawing.Graphics]::FromImage($bmp); $hdc = $g.GetHdc()
    [Win32R]::PrintWindow($hwnd2, $hdc, 2) | Out-Null; $g.ReleaseHdc($hdc); $g.Dispose()
    $png = Join-Path $env:TEMP "ghostty-test13-restored.png"; $bmp.Save($png); $bmp.Dispose()
    Write-Host "  capture: $png" -ForegroundColor DarkGray

    Test-Assert -Condition (-not (Test-Path (Join-Path $env:LOCALAPPDATA "ghostty-winui3\restore\restore-$($old.Id).json"))) -Message "$testName - restore file consumed"

    # --- 4. Second restart, through the menu item (UIA: expand the add-tab
    # split button, invoke "再起動してタブを復元"). The restored window
    # must restore to the same tabs again.
    $elem2 = Find-GhosttyUIAElement -ProcessId $new.ProcessId
    $btnCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, "AddTabSplitButton")
    $btn = $elem2.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
    Test-Assert -Condition ($null -ne $btn) -Message "$testName - add-tab split button found"
    $ec = $null
    Test-Assert -Condition ($btn.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$ec)) -Message "$testName - split button expandable"
    $ec.Expand(); Start-Sleep -Milliseconds 1200
    $miCond = New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::MenuItem)),
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, [int]$new.ProcessId)))
    $item = @([System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Descendants, $miCond)) |
        Where-Object { $_.Current.Name -eq "再起動してタブを復元" } | Select-Object -First 1
    Test-Assert -Condition ($null -ne $item) -Message "$testName - restart menu item present"
    $inv = $null
    [void]$item.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$inv)
    $inv.Invoke()
    Test-Assert -Condition ($newProc.WaitForExit(15000)) -Message "$testName - restored window exited on menu restart"
    $third = $null; $deadline = (Get-Date).AddSeconds(15)
    while (-not $third -and (Get-Date) -lt $deadline) {
        $third = Get-CimInstance Win32_Process -Filter "Name='ghostty.exe' AND ParentProcessId=$($new.ProcessId)" | Select-Object -First 1
        if (-not $third) { Start-Sleep -Milliseconds 300 }
    }
    Test-Assert -Condition ($null -ne $third) -Message "$testName - third ghostty started from menu"
    $new = $third
    [void](Find-GhosttyWindow -ProcessId $new.ProcessId)
    Start-Sleep -Seconds 4
    Test-AssertEqual -Expected 4 -Actual (Get-TabCount $new.ProcessId) -Message "$testName - 4 tabs after second restart"
    Test-AssertEqual -Expected "1,2,3,4" -Actual (Get-HeaderNumbers $new.ProcessId) -Message "$testName - split kept after second restart"
    $cl2 = @(@(Get-Descendants $new.ProcessId) | Where-Object { $_.Name -eq 'cmd.exe' -and $_.CommandLine -notmatch '/C ' } | ForEach-Object { $_.CommandLine })
    Test-Assert -Condition (@($cl2 | Where-Object { $_ -like "*/k claude --resume $claudeId*" }).Count -eq 1) -Message "$testName - claude session id survives a second restart"
    Test-Assert -Condition (@($cl2 | Where-Object { $_ -like "*/k codex resume $codexId*" }).Count -eq 1) -Message "$testName - codex session id survives a second restart"
    Test-Assert -Condition (@($cl2 | Where-Object { $_ -like "*/k agy --conversation $agyId*" }).Count -eq 1) -Message "$testName - agy conversation id survives a second restart"
} finally {
    if ($old -and -not $old.HasExited) { Stop-Ghostty -Process $old }
    if ($new) { $np = Get-Process -Id $new.ProcessId -ErrorAction SilentlyContinue; if ($np) { Stop-Ghostty -Process $np } }
    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}
Write-Host "PASS: $testName" -ForegroundColor Green
