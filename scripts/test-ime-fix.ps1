param(
    [string]$Base64Text
)

$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'ghostty\control-plane\winui3\sessions'
$entry = Get-ChildItem $root -Filter "*.session" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $entry) { throw "No session found" }

$map = @{}
Get-Content $entry.FullName | ForEach-Object {
    if ($_ -match '^(?<k>[^=]+)=(?<v>.*)$') { $map[$Matches.k] = $Matches.v }
}
$pipe = $map.pipe_name

$msg = "IME_INJECT|gemini|$Base64Text"

$client = [System.IO.Pipes.NamedPipeClientStream]::new('.', $pipe, [System.IO.Pipes.PipeDirection]::InOut)
try {
    $client.Connect(3000)
    $writer = [System.IO.StreamWriter]::new($client)
    $writer.AutoFlush = $true
    $writer.WriteLine($msg)
    $reader = [System.IO.StreamReader]::new($client)
    $reply = $reader.ReadToEnd()
    Write-Host "Reply: $reply"
} finally {
    $client.Dispose()
}
