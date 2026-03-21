@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
"C:\Users\Carlos\AppData\Local\Programs\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Launch.ps1"
