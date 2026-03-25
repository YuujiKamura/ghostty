Write-Host 'ABCDEFGHIJ' -NoNewline
Write-Host ''
Write-Host 'KLMNOPQRST' -NoNewline  
Write-Host ''
# Move cursor back up and to column 4 (on 'D')
[Console]::SetCursorPosition(3, [Console]::CursorTop - 2)
Start-Sleep -Seconds 30
