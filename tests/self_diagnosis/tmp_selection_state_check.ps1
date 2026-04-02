Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module "C:/Users/yuuji/ghostty-win/tests/winui3/test-helpers.psm1" -Force -WarningAction SilentlyContinue
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
$out = New-Object System.Collections.Generic.List[string]
function L([string]$s){ $out.Add($s) | Out-Null }

$exe='C:/Users/yuuji/ghostty-win/zig-out-winui3/bin/ghostty.exe'
$proc=Start-Ghostty -ExePath $exe
try{
  $hwnd=Find-GhosttyWindow -ProcessId $proc.Id -TimeoutMs 15000
  [Win32]::SetForegroundWindow($hwnd)|Out-Null
  Start-Sleep -Milliseconds 600
  $session=Register-GhosttyCP -ProcessId $proc.Id
  if(-not $session){$session=Find-GhosttyCP -ProcessId $proc.Id}
  if(-not $session){throw 'No CP session'}
  $pipe="ghostty-cp-$session"
  # Fallback from session metadata for exact pipe endpoint.
  $dir=Join-Path $env:LOCALAPPDATA 'ghostty/control-plane/winui3/sessions'
  $matched=$null
  if(Test-Path $dir){
    $candidates=Get-ChildItem $dir -Filter '*.session' -File | Sort-Object LastWriteTime -Descending
    $stem="$session-"
    foreach($sf in $candidates){
      if($sf.Name -eq "$session.session" -or $sf.Name.StartsWith($stem)){
        $matched=$sf
        break
      }
    }
    if(-not $matched){
      foreach($sf in $candidates){
        $lines=Get-Content $sf.FullName
        $hasPid=($lines | Where-Object { $_ -eq "pid=$($proc.Id)" }).Count -gt 0
        $hasSession=($lines | Where-Object { $_ -eq "session_name=$session" }).Count -gt 0
        if($hasPid -or $hasSession){
          $matched=$sf
          break
        }
      }
    }
  }
  if($matched){
    $lines=Get-Content $matched.FullName
    foreach($ln in $lines){
      if($ln -like 'pipe_path=*'){
        $pipePath=$ln.Substring(10).Trim()
        if($pipePath -match '^[\\/]{2}\.[\\/]+pipe[\\/]+(.+)$'){
          $pipe=$matches[1]
        }
      } elseif($ln -like 'pipe_name=*'){
        $pipe=$ln.Substring(10).Trim()
      }
    }
  }

  $state0=Send-CPRaw -pipe $pipe -cmd 'STATE|diag|0'
  L("state_before=$state0")

  $w=Get-WindowPosition -Hwnd $hwnd
  $x=$w.Left+180; $y=$w.Top+260
  Send-MouseDrag -X1 $x -Y1 $y -X2 ($x+16) -Y2 $y -Steps 4 -StepDelayMs 8
  Start-Sleep -Milliseconds 120
  $state1=Send-CPRaw -pipe $pipe -cmd 'STATE|diag|0'
  L("state_after_baseline=$state1")

  [Win32]::MoveWindow($hwnd,$w.Left+180,$w.Top+120,$w.Width,$w.Height,$true)|Out-Null
  Start-Sleep -Milliseconds 300
  $w2=Get-WindowPosition -Hwnd $hwnd
  $x2=$w2.Left+180; $y2=$w2.Top+260
  Send-MouseDrag -X1 $x2 -Y1 $y2 -X2 ($x2+16) -Y2 $y2 -Steps 4 -StepDelayMs 8
  Start-Sleep -Milliseconds 120
  $state2=Send-CPRaw -pipe $pipe -cmd 'STATE|diag|0'
  L("state_after_move=$state2")

  [Win32]::MoveWindow($hwnd,$w2.Left,$w2.Top,$w2.Width+120,$w2.Height+80,$true)|Out-Null
  Start-Sleep -Milliseconds 300
  $w3=Get-WindowPosition -Hwnd $hwnd
  $x3=$w3.Left+180; $y3=$w3.Top+260
  Send-MouseDrag -X1 $x3 -Y1 $y3 -X2 ($x3+16) -Y2 $y3 -Steps 4 -StepDelayMs 8
  Start-Sleep -Milliseconds 120
  $state3=Send-CPRaw -pipe $pipe -cmd 'STATE|diag|0'
  L("state_after_resize=$state3")
}
finally{
  if($proc -and -not $proc.HasExited){ Stop-Ghostty -Process $proc }
}
$log='C:/Users/yuuji/ghostty-win/tests/self_diagnosis/selection_state_check_run.log'
$out | Set-Content -Path $log -Encoding UTF8
Write-Output $log
