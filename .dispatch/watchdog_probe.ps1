param(
    [string]$SessionGlob = 'ghostty-winui3-teamg-smoke*'
)
$ErrorActionPreference = 'Stop'
$pipeRoot = [System.IO.Path]::Combine([System.IO.Path]::DirectorySeparatorChar + [System.IO.Path]::DirectorySeparatorChar + '.', 'pipe')
$pipes = Get-ChildItem -LiteralPath '\\.\pipe\' | Where-Object { $_.Name -like $SessionGlob }
if (-not $pipes) {
    Write-Host 'NO_PIPE'
    exit 1
}
$pipeName = ($pipes | Select-Object -First 1).Name
Write-Host "pipe=$pipeName"
foreach ($cmd in @('CAPABILITIES','WATCHDOG')) {
    $client = New-Object System.IO.Pipes.NamedPipeClientStream('.', $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
    $client.Connect(2000)
    $writer = New-Object System.IO.StreamWriter($client)
    $writer.AutoFlush = $true
    $reader = New-Object System.IO.StreamReader($client)
    $writer.WriteLine($cmd)
    $resp = $reader.ReadLine()
    Write-Host "[$cmd] $resp"
    $client.Dispose()
}
