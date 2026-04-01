$pipeName = 'ghostty-winui3-ghostty-37944-37944'
try {
    $pipe = [System.IO.Pipes.NamedPipeClientStream]::new('.', $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
    $pipe.Connect(3000)
    Write-Host "Connected to pipe"

    # Test PING
    $request = [System.Text.Encoding]::UTF8.GetBytes("PING`n")
    $pipe.Write($request, 0, $request.Length)
    $pipe.Flush()
    $buffer = New-Object byte[] 4096
    $bytesRead = $pipe.Read($buffer, 0, $buffer.Length)
    $response = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead)
    Write-Host "PING response: $response"
    $pipe.Dispose()

    # Test INPUT
    $pipe2 = [System.IO.Pipes.NamedPipeClientStream]::new('.', $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
    $pipe2.Connect(3000)
    $text = "echo pipe-test-42`n"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $b64 = [Convert]::ToBase64String($bytes)
    $inputReq = "INPUT|test-script|$b64`n"
    $inputBytes = [System.Text.Encoding]::UTF8.GetBytes($inputReq)
    $pipe2.Write($inputBytes, 0, $inputBytes.Length)
    $pipe2.Flush()
    $bytesRead2 = $pipe2.Read($buffer, 0, $buffer.Length)
    $response2 = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead2)
    Write-Host "INPUT response: $response2"
    $pipe2.Dispose()

} catch {
    Write-Host "Error: $($_.Exception.Message)"
}
