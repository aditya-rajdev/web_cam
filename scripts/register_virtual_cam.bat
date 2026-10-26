@echo off
echo PhoneCam Virtual WebCam Registration Script
echo ===========================================
echo.

:: Check for Administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] Administrator privileges required!
    echo Please right-click this script and select "Run as administrator".
    pause
    exit /b 1
)

:: Locate PhoneCamFilter.dll with Release build priority
set "DLL_PATH="

if exist "%~dp0..\build\windows\x64\runner\Release\PhoneCamFilter.dll" (
    set "DLL_PATH=%~dp0..\build\windows\x64\runner\Release\PhoneCamFilter.dll"
    echo [FOUND] Using Release build DLL: "%DLL_PATH%"
) else if exist "%~dp0..\build\windows\x64\runner\Debug\PhoneCamFilter.dll" (
    set "DLL_PATH=%~dp0..\build\windows\x64\runner\Debug\PhoneCamFilter.dll"
    echo [FOUND] Using Debug build DLL fallback: "%DLL_PATH%"
) else if exist "%~dp0..\PhoneCamFilter.dll" (
    set "DLL_PATH=%~dp0..\PhoneCamFilter.dll"
    echo [FOUND] Using parent directory DLL: "%DLL_PATH%"
) else if exist "%~dp0PhoneCamFilter.dll" (
    set "DLL_PATH=%~dp0PhoneCamFilter.dll"
    echo [FOUND] Using current directory DLL: "%DLL_PATH%"
)

if "%DLL_PATH%"=="" (
    echo [ERROR] PhoneCamFilter.dll not found!
    echo Please build the Windows project first using 'flutter build windows'.
    pause
    exit /b 1
)

echo.
echo Checking Code Signature status for "%DLL_PATH%"...
powershell -Command "$sig = Get-AuthenticodeSignature -FilePath '%DLL_PATH%'; Write-Host ('Authenticode Status: ' + $sig.Status); if ($sig.Status -ne 'Valid') { exit 10 }"
set SIG_STATUS=%errorLevel%

if %SIG_STATUS% neq 0 (
    echo.
    echo [NOTICE] PhoneCamFilter.dll is unsigned or untrusted.
    echo Attempting to sign DLL using Local Development Certificate for Windows Code Integrity compliance...
    powershell -Command "$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like '*PhoneCam Local Development*' } | Select-Object -First 1; if (-not $cert) { $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=PhoneCam Local Development Code Signing' -CertStoreLocation 'Cert:\LocalMachine\My'; $rootStore = Get-Item 'Cert:\LocalMachine\Root'; $rootStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite); $rootStore.Add($cert); $rootStore.Close(); $pubStore = Get-Item 'Cert:\LocalMachine\TrustedPublisher'; $pubStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite); $pubStore.Add($cert); $pubStore.Close(); }; Set-AuthenticodeSignature -FilePath '%DLL_PATH%' -Certificate $cert"
)

echo.
echo Registering DLL in Windows System Registry...
echo Path: "%DLL_PATH%"

regsvr32.exe /s "%DLL_PATH%"
set REGSVR_EXIT=%errorLevel%

if %REGSVR_EXIT% equ 0 (
    echo.
    echo [SUCCESS] PhoneCam Virtual WebCam registered successfully!
    echo InprocServer32 now points to: "%DLL_PATH%"
    echo You can select "PhoneCam" as your camera in OBS Studio, Zoom, Google Meet, or Teams.
) else (
    echo.
    echo [ERROR] regsvr32.exe failed with exit code %REGSVR_EXIT%.
    if %REGSVR_EXIT% equ 3 (
        echo [DIAGNOSTIC] Exit code 3 indicates DLL loading blocked by Windows Code Integrity / App Control policy.
        powershell -Command "Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 3 | Format-List TimeCreated, Id, Message"
    )
    exit /b %REGSVR_EXIT%
)

echo.
pause
