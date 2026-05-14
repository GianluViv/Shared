@echo off
setlocal

:: Check PowerShell is available
where powershell >nul 2>&1
if errorlevel 1 (
    echo ERROR: PowerShell not found. Install PowerShell and retry.
    pause
    exit /b 1
)

:: Run sync.ps1 from the same directory as this .bat
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync.ps1"

if errorlevel 1 (
    echo.
    echo Sync failed. See messages above.
    pause
    exit /b 1
)

endlocal
