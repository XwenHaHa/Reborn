@echo off
REM Double-click to RUN the game (not the editor).
REM Godot 4.7.2 stable, project at E:\Reborn\Game\Reborn
set "GODOT=E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
set "PROJ=%~dp0..\Game\Reborn"
if not exist "%GODOT%" (
  echo [ERROR] Godot not found: %GODOT%
  echo Edit this file and set GODOT to your Godot 4.x executable.
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%PROJ%"
