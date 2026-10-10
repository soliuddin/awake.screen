@echo off
rem Starts the floating Stay Awake button. Keep this file next to StayAwake.ps1.
rem ExecutionPolicy Bypass applies to this one PowerShell process only.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "%~dp0StayAwake.ps1"
