@echo off
TITLE Instalador Enlace360 - v3.2
color 0B

:: Auto-elevar a Administrador
net session >nul 2>&1
if NOT %errorLevel% == 0 (
    echo Solicitando permisos de Administrador...
    powershell -Command "Start-Process -FilePath '%~dpnx0' -Verb RunAs"
    exit /b
)

echo =======================================================
echo   INSTALADOR ENLACE360 - AGENTE DE MONITOREO
echo =======================================================
echo.

echo [1/4] Deteniendo agente anterior si existe...
schtasks /End /TN "Enlace360_Agent" >nul 2>&1
schtasks /Delete /TN "Enlace360_Agent" /F >nul 2>&1
taskkill /F /IM powershell.exe >nul 2>&1
echo       Hecho.

echo [2/4] Creando carpeta segura...
if not exist "C:\KioskNetMonitor" mkdir "C:\KioskNetMonitor"
echo       Hecho.

echo [3/4] Descargando agente desde GitHub...
powershell -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/Enlace360/Monitoreo-de-red-/main/Agente_Enlace360_Service.ps1' -OutFile 'C:\KioskNetMonitor\Agente_Enlace360_Service.ps1' -UseBasicParsing"
echo       Hecho.

set PS_SCRIPT=%TEMP%\Enlace360_Setup.ps1
echo Clear-Host > "%PS_SCRIPT%"
echo Write-Host "======================================================" -ForegroundColor Cyan >> "%PS_SCRIPT%"
echo Write-Host "   INSTALADOR ENLACE360 - CONFIGURACION DEL KIOSCO" -ForegroundColor Cyan >> "%PS_SCRIPT%"
echo Write-Host "======================================================" -ForegroundColor Cyan >> "%PS_SCRIPT%"
echo $configFile = "C:\KioskNetMonitor\config.json" >> "%PS_SCRIPT%"
echo if (-not (Test-Path $configFile)) { >> "%PS_SCRIPT%"
echo     $ClientName = Read-Host "1. Nombre del Cliente (ej. Salfa)" >> "%PS_SCRIPT%"
echo     $Location = Read-Host "2. Sucursal (ej. Chevrolet Rondizonni)" >> "%PS_SCRIPT%"
echo     $KioskName = Read-Host "3. Nombre del Kiosco (ej. Totem Entrada)" >> "%PS_SCRIPT%"
echo     @{ ClientName = $ClientName; Location = $Location; KioskName = $KioskName } ^| ConvertTo-Json ^| Set-Content $configFile >> "%PS_SCRIPT%"
echo } else { Write-Host "[INFO] Configuracion previa detectada. Se conserva." -ForegroundColor Yellow } >> "%PS_SCRIPT%"
echo Write-Host "" >> "%PS_SCRIPT%"
echo Write-Host "[4/4] Registrando servicio permanente..." -ForegroundColor Green >> "%PS_SCRIPT%"
echo $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File C:\KioskNetMonitor\Agente_Enlace360_Service.ps1" >> "%PS_SCRIPT%"
echo $trigger = New-ScheduledTaskTrigger -AtStartup >> "%PS_SCRIPT%"
echo $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest >> "%PS_SCRIPT%"
echo $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DontStopOnIdleEnd  >> "%PS_SCRIPT%"
echo Register-ScheduledTask -TaskName "Enlace360_Agent" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force ^| Out-Null >> "%PS_SCRIPT%"
echo Start-ScheduledTask -TaskName "Enlace360_Agent" >> "%PS_SCRIPT%"
echo Write-Host "" >> "%PS_SCRIPT%"
echo Write-Host "======================================================" -ForegroundColor Cyan >> "%PS_SCRIPT%"
echo Write-Host "[EXITO] Agente instalado. Ya puedes cerrar esta ventana." -ForegroundColor Green >> "%PS_SCRIPT%"
echo Write-Host "El kiosco aparecera en el Dashboard en menos de 30 seg." -ForegroundColor Green >> "%PS_SCRIPT%"

powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%PS_SCRIPT%"

echo.
pause
