@echo off
setlocal
set GHOSTTY=%~dp0..\..\zig-out-winui3\bin\ghostty.exe
set AGENT_CTL=%USERPROFILE%\agent-relay\target\debug\agent-ctl.exe
set DEMO=%~dp0ghost_demo.exe

if not exist "%GHOSTTY%" (
    echo ghostty.exe not found. Build first: ./build-winui3.sh -Doptimize=ReleaseFast
    pause
    exit /b 1
)
if not exist "%DEMO%" (
    echo ghost_demo.exe not found. Build first: zig build-exe tools/ghost-demo/ghost_demo.zig -OReleaseFast
    pause
    exit /b 1
)

echo [demo] Starting Ghostty...
start "" "%GHOSTTY%"
timeout /t 8 /nobreak >nul

echo [demo] Finding CP session...
for /f "tokens=3 delims== " %%s in ('%AGENT_CTL% list --alive-only 2^>nul ^| findstr /c:"ghostty" ^| findstr /c:"ALIVE"') do (
    %AGENT_CTL% ping %%s >nul 2>&1 && (
        echo [demo] Session: %%s
        %AGENT_CTL% send %%s "%DEMO% --fps 60" --enter
        echo [demo] Running at 60fps.
        goto :done
    )
)
echo [demo] ERROR: No live session found. Run ghost_demo.exe manually.
:done
endlocal
