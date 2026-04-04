Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$_repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $_repoRoot "tests/winui3/test-helpers.psm1") -Force -WarningAction SilentlyContinue

function Send-CPRaw([string]$pipe,[string]$cmd){
  $client=New-Object System.IO.Pipes.NamedPipeClientStream('.', $pipe, [System.IO.Pipes.PipeDirection]::InOut)
  $client.Connect(7000)
  $w=New-Object System.IO.StreamWriter($client); $w.AutoFlush=$true
  $r=New-Object System.IO.StreamReader($client)
  $w.WriteLine($cmd)
  $resp=$r.ReadToEnd()
  $client.Dispose()
  return $resp
}

function Resolve-CPPipeName([string]$session,[int]$procId){
  $pipe="ghostty-cp-$session"
  $dir=Join-Path $env:LOCALAPPDATA 'ghostty/control-plane/winui3/sessions'
  if(-not (Test-Path $dir)){ return $pipe }

  $candidates=Get-ChildItem $dir -Filter '*.session' -File | Sort-Object LastWriteTime -Descending
  $match=$null
  $stem="$session-"
  foreach($sf in $candidates){
    if($sf.Name -eq "$session.session" -or $sf.Name.StartsWith($stem)){
      $match=$sf
      break
    }
  }
  if(-not $match){
    foreach($sf in $candidates){
      $lines=Get-Content $sf.FullName
      $hasPid=($lines | Where-Object { $_ -eq "pid=$procId" }).Count -gt 0
      $hasSession=($lines | Where-Object { $_ -eq "session_name=$session" }).Count -gt 0
      if($hasPid -or $hasSession){
        $match=$sf
        break
      }
    }
  }
  if(-not $match){ return $pipe }

  $lines=Get-Content $match.FullName
  foreach($ln in $lines){
    if($ln -like 'pipe_path=*'){
      $pipePath=$ln.Substring(10).Trim()
      if($pipePath -match '^[\\/]{2}\.[\\/]+pipe[\\/]+(.+)$'){
        return $matches[1]
      }
    }
  }
  return $pipe
}

$out=New-Object System.Collections.Generic.List[string]
function L([string]$s){ $out.Add($s) | Out-Null }

$exe=Join-Path $_repoRoot 'zig-out-winui3/bin/ghostty.exe'
$proc=Start-Ghostty -ExePath $exe
try{
  $hwnd=Find-GhosttyWindow -ProcessId $proc.Id -TimeoutMs 15000
  [Win32]::SetForegroundWindow($hwnd)|Out-Null
  Start-Sleep -Milliseconds 600

  $session=Register-GhosttyCP -ProcessId $proc.Id
  if(-not $session){$session=Find-GhosttyCP -ProcessId $proc.Id}
  if(-not $session){throw 'No CP session'}
  $pipe=Resolve-CPPipeName -session $session -procId $proc.Id
  L("session=$session pipe=$pipe")

  # Fill terminal with deterministic text so drag rows likely hit glyphs.
  $ok=Send-GhosttyInput -SessionName $session -Text 'for /L %i in (1,1,40) do @echo ROW-%i-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
  Start-Sleep -Milliseconds 1300
  L("seed_send_ok=$ok")

  $w=Get-WindowPosition -Hwnd $hwnd
  $rx1=180
  $drag=140

  $state0=Send-CPRaw -pipe $pipe -cmd 'STATE|diag|0'
  L("state_initial=$state0")
  $tail0=Send-CPRaw -pipe $pipe -cmd 'TAIL|diag|0'
  L("tail_initial=$tail0")

  # Verify synthetic keyboard input reaches terminal at all.
  Send-KeyPress -VirtualKey 0x5A # 'Z'
  Start-Sleep -Milliseconds 80
  Send-KeyPress -VirtualKey 0x08 # Backspace
  Start-Sleep -Milliseconds 80
  $stateKey=Send-CPRaw -pipe $pipe -cmd 'STATE|diag|0'
  L("state_after_key_probe=$stateKey")
  $tailKey=Send-CPRaw -pipe $pipe -cmd 'TAIL|diag|0'
  L("tail_after_key_probe=$tailKey")

  for($ry=80; $ry -le 520; $ry+=24){
    $x1=$w.Left+$rx1
    $y1=$w.Top+$ry
    Send-MouseClick -X $x1 -Y $y1 -Button Left
    Start-Sleep -Milliseconds 50
    Send-MouseDrag -X1 $x1 -Y1 $y1 -X2 ($x1+$drag) -Y2 $y1 -Steps 8 -StepDelayMs 10
    Start-Sleep -Milliseconds 100
    $st=Send-CPRaw -pipe $pipe -cmd 'STATE|diag|0'
    $sel = if($st -match 'selection=(\d+)'){ $matches[1] } else { '?' }
    L("ry=$ry selection=$sel state=$st")
    # clear selection before next probe
    Send-KeyPress -VirtualKey 0x1B
    Start-Sleep -Milliseconds 50
  }
}
finally{
  if($proc -and -not $proc.HasExited){ Stop-Ghostty -Process $proc }
}

$log=Join-Path $PSScriptRoot 'selection_hotspot_run.log'
$out | Set-Content -Path $log -Encoding UTF8
Write-Output $log
