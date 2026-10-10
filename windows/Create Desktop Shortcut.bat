@echo off
rem Puts a "Stay Awake" shortcut with the Stay Awake icon on your desktop.
rem Keep this file next to Start Stay Awake.bat, StayAwake.ps1 and stay-awake.ico.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Desktop')+'\Stay Awake.lnk');$s.TargetPath='%~dp0Start Stay Awake.bat';$s.WorkingDirectory='%~dp0';$s.IconLocation='%~dp0stay-awake.ico';$s.WindowStyle=7;$s.Save()"
echo Shortcut created on your desktop.
pause
