@echo off
if not exist "%~dp0game\stunt.exe" (
  echo Run Install.cmd first.
  pause
  exit /b 1
)
cd /d "%~dp0game"
start "" stunt.exe
