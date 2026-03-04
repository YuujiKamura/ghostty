param(
    [string]$OutFile = "C:\Users\yuuji\ghostty-win\visual_smoke_test_new.png",
    [int]$WaitSec = 8
)

# Set environment variables for stable rendering
$env:GHOSTTY_WINUI3_ENABLE_TABVIEW = "true"
$env:GHOSTTY_WINUI3_ENABLE_TABVIEW_HANDLERS = "true"
$env:GHOSTTY_WINUI3_TABVIEW_APPEND_ITEM = "true"
$env:GHOSTTY_WINUI3_TABVIEW_SELECT_FIRST = "true"
$env:GHOSTTY_WINUI3_TABVIEW_EMPTY = "false"

Write-Host "Starting Ghostty for visual smoke test..."
$exePath = "C:\Users\yuuji\ghostty-win\zig-out\bin\ghostty.exe"
$p = Start-Process -FilePath $exePath -WorkingDirectory "C:\Users\yuuji\ghostty-win" -PassThru
Start-Sleep -Seconds $WaitSec

Write-Host "Capturing screenshot..."
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$Screen = [System.Windows.Forms.Screen]::PrimaryScreen
$Bitmap = New-Object System.Drawing.Bitmap($Screen.Bounds.Width, $Screen.Bounds.Height)
$Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
$Graphics.CopyFromScreen($Screen.Bounds.X, $Screen.Bounds.Y, 0, 0, $Bitmap.Size)
$Bitmap.Save($OutFile)
$Graphics.Dispose()
$Bitmap.Dispose()
Write-Host "Screenshot saved to $OutFile"

if (!$p.HasExited) {
    Write-Host "Stopping Ghostty process..."
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "Ghostty exited prematurely with code $($p.ExitCode)"
}
