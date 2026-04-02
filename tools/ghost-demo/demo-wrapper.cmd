@echo off
chcp 65001 >nul
python "%~dp0play.py" --fps 60
echo.
echo === Demo finished. Press any key to close ===
pause >nul
