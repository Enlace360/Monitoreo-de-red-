@echo off
TITLE Instalador Enlace360 - Nivel Dios
color 0B

:: Auto-elevar a Administrador
net session >nul 2>&1
if NOT %errorLevel% == 0 (
    echo Solicitando permisos de Administrador...
    powershell -Command "Start-Process -FilePath '%~dpnx0' -Verb RunAs"
    exit /b
)

echo [1/3] Deteniendo agente anterior si existe...
schtasks /End /TN "Enlace360_Agent" >nul 2>&1
schtasks /Delete /TN "Enlace360_Agent" /F >nul 2>&1
taskkill /F /IM powershell.exe >nul 2>&1
echo       Hecho.

echo [2/3] Creando entorno seguro en C:\KioskNetMonitor...
if not exist "C:\KioskNetMonitor" mkdir "C:\KioskNetMonitor"

copy /Y "%~dp0Agente_Enlace360_Service.ps1" "C:\KioskNetMonitor\Agente_Enlace360_Service.ps1"

set PS_SCRIPT=%TEMP%\Enlace360_Setup.ps1
echo Clear-Host > "%PS_SCRIPT%"
echo Write-Host "======================================================" -ForegroundColor Cyan >> "%PS_SCRIPT%"
echo Write-Host "   INSTALADOR DE SERVICIO (FIREPROOF) - ENLACE360" -ForegroundColor Cyan >> "%PS_SCRIPT%"
echo Write-Host "======================================================" -ForegroundColor Cyan >> "%PS_SCRIPT%"
echo $configFile = "C:\KioskNetMonitor\config.json" >> "%PS_SCRIPT%"
echo if (-not (Test-Path $configFile)) { >> "%PS_SCRIPT%"
echo     $ClientName = Read-Host "1. Ingresa Nombre del Cliente (ej. Cencosud)" >> "%PS_SCRIPT%"
echo     $Location = Read-Host "2. Ingresa Ubicacion o Sucursal (ej. Mall Costanera)" >> "%PS_SCRIPT%"
echo     $KioskName = Read-Host "3. Ingresa Identificador del Kiosco (ej. 21 Pasarela - N2)" >> "%PS_SCRIPT%"
echo     @{ ClientName = $ClientName; Location = $Location; KioskName = $KioskName } ^| ConvertTo-Json ^| Set-Content $configFile >> "%PS_SCRIPT%"
echo } else { Write-Host "[INFO] Configuracion previa detectada." -ForegroundColor Yellow } >> "%PS_SCRIPT%"
echo Write-Host "Registrando Tarea Programada (SYSTEM)..." -ForegroundColor Green >> "%PS_SCRIPT%"
echo $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File C:\KioskNetMonitor\Agente_Enlace360_Service.ps1" >> "%PS_SCRIPT%"
echo $trigger = New-ScheduledTaskTrigger -AtStartup >> "%PS_SCRIPT%"
echo $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest >> "%PS_SCRIPT%"
echo $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit 0 >> "%PS_SCRIPT%"
echo Register-ScheduledTask -TaskName "Enlace360_Agent" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force ^| Out-Null >> "%PS_SCRIPT%"
echo Start-ScheduledTask -TaskName "Enlace360_Agent" >> "%PS_SCRIPT%"
echo Write-Host "======================================================" -ForegroundColor Cyan >> "%PS_SCRIPT%"
echo Write-Host "[EXITO] Agente instalado como demonio oculto." -ForegroundColor Green >> "%PS_SCRIPT%"
echo Write-Host "El Agente ya esta corriendo silenciosamente. Sobrevivira a reinicios." -ForegroundColor Green >> "%PS_SCRIPT%"

powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%PS_SCRIPT%"

echo.
pause
