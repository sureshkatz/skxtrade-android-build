@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0BUILD_ANDROID.ps1" %*
if errorlevel 1 (
  echo Build stopped. Read the error above.
  pause
  exit /b 1
)
pause
