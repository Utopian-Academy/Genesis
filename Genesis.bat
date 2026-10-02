@echo off
rem Opens Genesis. On the first run it downloads the photographic assets
rem and builds the materials and plants (a few minutes, once).
setlocal
set "HERE=%~dp0"
set "GODOT=%GENESIS_GODOT%"
if "%GODOT%"=="" (
  for %%F in ("%USERPROFILE%\tools\godot\Godot_v4.7*_win64.exe") do if not "%%~nxF"=="%%~nF_console.exe" set "GODOT=%%F"
)
if "%GODOT%"=="" (
  where godot >nul 2>nul && set "GODOT=godot"
)
if "%GODOT%"=="" (
  echo Godot 4.7 was not found. Download it from https://godotengine.org and set
  echo GENESIS_GODOT to the Godot executable, then run this again.
  pause
  exit /b 1
)
if not exist "%HERE%genesis_data\materials\brick.tres" (
  echo First run: getting the photographic skies, materials and plants ready...
  python "%HERE%tools\setup.py"
)
start "" "%GODOT%" --editor --path "%HERE%."
