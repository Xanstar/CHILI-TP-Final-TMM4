@echo off
rem Abre el editor de Godot en la carpeta del proyecto original.
setlocal
cd /d "%~dp0"

call "%~dp0_find-godot.bat" || exit /b 1
"%GODOT%" --editor --path Godot
