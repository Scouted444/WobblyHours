@echo off
REM Double-click me to make a launcher update (see README). Export the game from Godot first.
setlocal
cd /d "%~dp0"
set "REPO="
if exist release_repo.txt set /p REPO=<release_repo.txt
if "%REPO%"=="" set /p REPO=Your GitHub repo (like yourname/wobbly-hours): 
echo %REPO%>release_repo.txt
set /p NOTES=What's new in this version (optional): 
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\make_release.ps1" -Repo "%REPO%" -Notes "%NOTES%"
echo.
explorer "%~dp0release"
pause
