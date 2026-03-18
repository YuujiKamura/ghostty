@echo off
set GHOSTTY=%~dp0..\..\zig-out-winui3\bin\ghostty.exe
set WRAPPER=%~dp0demo-wrapper.cmd

if not exist "%GHOSTTY%" (
    echo ghostty.exe not found. Build first: ./build-winui3.sh
    pause
    exit /b 1
)

start "" "%GHOSTTY%" --font-size=7 -e "%WRAPPER%"
