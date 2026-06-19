@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%debug_models.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%"

endlocal

pause
