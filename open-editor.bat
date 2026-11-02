@echo off
rem Abre solo el editor de Godot en este proyecto.
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "GODOT="
where godot >nul 2>nul && set "GODOT=godot"
if not defined GODOT (
    for %%d in ("%LOCALAPPDATA%\Programs\Godot" "%~dp0tools") do (
        for %%f in ("%%~d\Godot_v*_win64.exe") do set "GODOT=%%~ff"
    )
)
if not defined GODOT (
    echo No encuentro Godot.
    echo Instalalo, o deja el ejecutable en %%LOCALAPPDATA%%\Programs\Godot o en tools\.
    pause
    exit /b 1
)

"%GODOT%" --editor --path game
