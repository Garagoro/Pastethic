@echo off
setlocal

cd /d "%~dp0"

echo Building Pasthetic all-in-one...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\build_allinone.ps1" -UpdateManifest

if errorlevel 1 (
    echo.
    echo Build failed.
    pause
    exit /b 1
)

echo.
echo Done. Generated:
echo %~dp0Pasthetic allinone.lua
echo.
pause
