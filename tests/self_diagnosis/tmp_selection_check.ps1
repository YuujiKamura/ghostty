Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot "../winui3/test-helpers.psm1") -Force -WarningAction SilentlyContinue
$out = New-Object System.Collections.Generic.List[string]
function L([string]$s){ $out.Add($s) | Out-Null }
function Send-KeyChord([uint16[]]$DownVks,[uint16]$KeyVk){
  $inputs = New-Object System.Collections.Generic.List[object]
  foreach($vk in $DownVks){$d=New-Object INPUT;$d.Type=[Win32]::INPUT_KEYBOARD;$d.ki.wVk=$vk;$inputs.Add($d)|Out-Null}
  $kd=New-Object INPUT;$kd.Type=[Win32]::INPUT_KEYBOARD;$kd.ki.wVk=$KeyVk;$inputs.Add($kd)|Out-Null
  $ku=New-Object INPUT;$ku.Type=[Win32]::INPUT_KEYBOARD;$ku.ki.wVk=$KeyVk;$ku.ki.dwFlags=[Win32]::KEYEVENTF_KEYUP;$inputs.Add($ku)|Out-Null
  foreach($vk in ($DownVks|Sort-Object -Descending)){$u=New-Object INPUT;$u.Type=[Win32]::INPUT_KEYBOARD;$u.ki.wVk=$vk;$u.ki.dwFlags=[Win32]::KEYEVENTF_KEYUP;$inputs.Add($u)|Out-Null}
  [Win32]::SendInput([uint32]$inputs.Count,$inputs.ToArray(),[Runtime.InteropServices.Marshal]::SizeOf([type][INPUT]))|Out-Null
}
function Copy-Selected(){ Send-KeyChord -DownVks @(0x11,0x10) -KeyVk 0x43; Start-Sleep -Milliseconds 80; Send-KeyChord -DownVks @(0x11) -KeyVk 0x43; Start-Sleep -Milliseconds 120 }
function Sample-Selection([IntPtr]$hwnd,[int]$rx,[int]$ry){
  $w=Get-WindowPosition -Hwnd $hwnd
  $x=$w.Left+$rx; $y=$w.Top+$ry
  try{Set-Clipboard -Value ''}catch{}
  Send-MouseDrag -X1 $x -Y1 $y -X2 ($x+12) -Y2 $y -Steps 4 -StepDelayMs 8
  Copy-Selected
  $clip=''; try{$clip=(Get-Clipboard -Raw)}catch{}
  if($null -eq $clip){$clip=''}
  return @{ x=$x; y=$y; clip=$clip }
}
$_repoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
$exe=Join-Path $_repoRoot 'zig-out-winui3/bin/ghostty.exe'
$proc=Start-Ghostty -ExePath $exe
try{
  $hwnd=Find-GhosttyWindow -ProcessId $proc.Id -TimeoutMs 15000
  [Win32]::SetForegroundWindow($hwnd)|Out-Null
  Start-Sleep -Milliseconds 600
  $session=Register-GhosttyCP -ProcessId $proc.Id
  if(-not $session){$session=Find-GhosttyCP -ProcessId $proc.Id}
  if(-not $session){throw 'No CP session'}
  $marker='ALIGNCHK:0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
  $ok=Send-GhosttyInput -SessionName $session -Text "echo $marker"
  Start-Sleep -Milliseconds 1200
  $tail=Get-GhosttyOutput -SessionName $session
  L("marker_seen=$($tail -match [regex]::Escape($marker)) session=$session send_ok=$ok")
  $rx=180; $ry=260
  $a=Sample-Selection -hwnd $hwnd -rx $rx -ry $ry
  L(("baseline clip='{0}' at ({1},{2})" -f $a.clip,$a.x,$a.y))
  $w=Get-WindowPosition -Hwnd $hwnd
  [Win32]::MoveWindow($hwnd,$w.Left+180,$w.Top+120,$w.Width,$w.Height,$true)|Out-Null
  Start-Sleep -Milliseconds 400
  $b=Sample-Selection -hwnd $hwnd -rx $rx -ry $ry
  L(("after-move clip='{0}' at ({1},{2})" -f $b.clip,$b.x,$b.y))
  $w2=Get-WindowPosition -Hwnd $hwnd
  [Win32]::MoveWindow($hwnd,$w2.Left,$w2.Top,$w2.Width+140,$w2.Height+80,$true)|Out-Null
  Start-Sleep -Milliseconds 500
  $c=Sample-Selection -hwnd $hwnd -rx $rx -ry $ry
  L(("after-resize clip='{0}' at ({1},{2})" -f $c.clip,$c.x,$c.y))
  L("same_baseline_vs_move=$($a.clip -eq $b.clip)")
  L("same_baseline_vs_resize=$($a.clip -eq $c.clip)")
}
finally{
  if($proc -and -not $proc.HasExited){ Stop-Ghostty -Process $proc }
}
$log=Join-Path $PSScriptRoot "selection_check_run.log"
$out | Set-Content -Path $log -Encoding UTF8
Write-Output $log
