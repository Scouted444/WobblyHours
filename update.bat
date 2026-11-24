@echo off
REM Wobbly Hours updater: drag the new wobbly_hours.zip onto this file (or run it and paste the path).
REM It backs up the current game first, then copies the new files over it. Your settings and characters
REM (stored in your user folder) are never touched.
setlocal
set "ZIP=%~1"
if "%ZIP%"=="" set /p ZIP=Path to the new wobbly_hours.zip: 
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\update.ps1" -Zip "%ZIP%"
pause
