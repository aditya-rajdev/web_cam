@echo off
:: PhoneCam DirectShow Virtual Camera Registration Script
:: Must be run with Administrator privileges.

net session >nul 2>&1
if %errorLevel% == 0 (
    echo [INFO] Running with Administrator privileges...
) else (
    echo [ERROR] This script must be run as Administrator!
    echo Please right-click register_virtual_cam.bat and select 'Run as administrator'.
    pause
    exit /b 1
)

set DLL_PATH=%~dp0..\windows\runner\native\PhoneCamFilter.dll

if not exist "%DLL_PATH%" (
    echo [WARNING] Local build DLL not found at %DLL_PATH%.
    echo Searching for installed DLL...
    set DLL_PATH=%APPDATA%\PhoneCam\PhoneCamFilter.dll
)

echo Registering PhoneCam DirectShow Virtual Camera filter...
regsvr32 /s "%DLL_PATH%"

if %errorLevel% == 0 (
    echo [SUCCESS] PhoneCam Virtual Camera registered successfully!
    echo It is now available in OBS Studio, Zoom, Google Meet, MS Teams, and Discord.
) else (
    echo [ERROR] Failed to register PhoneCam Virtual Camera filter.
)

pause
