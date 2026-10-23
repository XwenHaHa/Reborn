@echo off
REM Double-click to open the project in the Godot EDITOR.
set "GODOT=E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
set "PROJ=%~dp0..\Game\Reborn"
if not exist "%GODOT%" (
  echo [ERROR] Godot not found: %GODOT%
  echo Edit this file and set GODOT to your Godot 4.x executable.
  pause
  exit /b 1
)
start "" "%GODOT%" --editor --path "%PROJ%"
