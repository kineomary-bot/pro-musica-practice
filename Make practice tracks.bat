@echo off
cd /d "%~dp0"
echo Making the practice tracks. This can take a few minutes. Please wait...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
echo.
pause
