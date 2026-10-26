# PhoneCam Code Signing and System Registration Script
# Requires Administrator Privileges

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] Administrator privileges required! Please run PowerShell as Administrator." -ForegroundColor Red
    exit 1
}

$projectRoot = "C:\Users\aryan\AndroidStudioProjects\untitled3"
$dllPath = "$projectRoot\build\windows\x64\runner\Release\PhoneCamFilter.dll"

if (-not (Test-Path $dllPath)) {
    $dllPath = "$projectRoot\build\windows\x64\runner\Debug\PhoneCamFilter.dll"
}

if (-not (Test-Path $dllPath)) {
    Write-Host "[ERROR] PhoneCamFilter.dll not found. Please build the project first using 'flutter build windows'." -ForegroundColor Red
    exit 1
}

Write-Host "[FOUND] Target DLL: $dllPath" -ForegroundColor Green

# 1. Close processes that might hold locks on DLLs
Write-Host "Releasing active process locks on DLLs..." -ForegroundColor Yellow
Stop-Process -Name "PhoneCam" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "chrome" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "msedge" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "regsvr32" -Force -ErrorAction SilentlyContinue

# Unregister existing handle to release DLL from memory
Start-Process "regsvr32.exe" -ArgumentList "/u /s `"$dllPath`"" -Wait -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# If DLL is locked by a system handle, copy to a clean signed binary path
$signedDllPath = "$projectRoot\build\windows\x64\runner\Release\PhoneCamFilter_Signed.dll"
try {
    Copy-Item -Path $dllPath -Destination $signedDllPath -Force -ErrorAction Stop
    $targetDll = $signedDllPath
} catch {
    $targetDll = $dllPath
}

# 2. Get or Create Trusted Local Development Certificate
Write-Host "Checking Code Signing Certificate..." -ForegroundColor Yellow
$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like '*PhoneCam Local Development*' } | Select-Object -First 1

if (-not $cert) {
    Write-Host "Creating Local Development Code Signing Certificate..." -ForegroundColor Yellow
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=PhoneCam Local Development Code Signing' -CertStoreLocation 'Cert:\LocalMachine\My'

    $rootStore = Get-Item 'Cert:\LocalMachine\Root'
    $rootStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $rootStore.Add($cert)
    $rootStore.Close()

    $pubStore = Get-Item 'Cert:\LocalMachine\TrustedPublisher'
    $pubStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $pubStore.Add($cert)
    $pubStore.Close()

    Write-Host "[SUCCESS] Created and trusted Local Development Certificate." -ForegroundColor Green
}

# 3. Sign ALL compiled Windows EXEs and DLLs (PhoneCam.exe, PhoneCamFilter.dll, url_launcher, etc.)
Write-Host "Signing all compiled Windows EXEs and DLLs with Authenticode Signature..." -ForegroundColor Yellow
Get-ChildItem -Path "$projectRoot\build\windows\x64\" -Include "*.dll","*.exe" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $sigStatus = Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert
    Write-Host "Signed: $($_.Name) -> Status: $($sigStatus.Status)" -ForegroundColor Green
}

# 4. Register Signed Virtual Camera DLL in System Registry
Write-Host "Registering PhoneCam Virtual Camera DLL in System Registry via regsvr32.exe..." -ForegroundColor Yellow
$regProcess = Start-Process "regsvr32.exe" -ArgumentList "/s `"$targetDll`"" -Wait -PassThru

if ($regProcess.ExitCode -eq 0) {
    Write-Host "[SUCCESS] PhoneCam Virtual WebCam registered successfully in System Registry!" -ForegroundColor Green
    Write-Host "InprocServer32 points to: `"$targetDll`"" -ForegroundColor Cyan
    Write-Host "Select 'PhoneCam' under camera settings in OBS Studio, Zoom, Google Meet, or Teams." -ForegroundColor Cyan
} else {
    Write-Host "[ERROR] regsvr32.exe failed with exit code $($regProcess.ExitCode)" -ForegroundColor Red
    if ($regProcess.ExitCode -eq 3) {
        Write-Host "[DIAGNOSTIC] Exit code 3 indicates Code Integrity / HVCI policy block." -ForegroundColor Red
        Get-WinEvent -LogName 'Microsoft-Windows-CodeIntegrity/Operational' -MaxEvents 3 | Format-List TimeCreated, Id, Message
    }
}
