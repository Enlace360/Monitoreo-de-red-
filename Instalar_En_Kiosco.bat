@echo off
color 0B
title Instalador Enlace 360 - Kiosk Monitor
echo ===================================================
echo     INSTALADOR DE AGENTE - ENLACE 360 (Supabase)
echo ===================================================
echo.

:: 1. Comprobar permisos de Administrador
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ALERTA] Este instalador necesita permisos de Administrador.
    echo Solicitando permisos automaticamente...
    goto UACPrompt
) else (
    goto Install
)

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /B

:Install
echo [1/3] Creando directorio seguro en C:\KioskNetMonitor...
if not exist "C:\KioskNetMonitor" mkdir "C:\KioskNetMonitor"

echo.
color 0E
echo ===================================================
echo   DATOS DE IDENTIFICACION (INGRESO MANUAL)
echo ===================================================
set /p KIOSCO="1. Escribe el NOMBRE DEL EQUIPO (Ej. TOTEM-PISO1) y presiona Enter: "
set /p CLIENTE="2. Escribe el NOMBRE DEL CLIENTE (Ej. Cencosud) y presiona Enter: "
set /p SUCURSAL="3. Escribe la SUCURSAL (Ej. Costanera Center) y presiona Enter: "
echo.
color 0B

echo [2/3] Configurando credenciales y copiando el agente...
if not exist "%~dp0KioskNetMonitor_Supabase.ps1" (
    color 4F
    echo [ERROR CRITICO] No se encontro el archivo "KioskNetMonitor_Supabase.ps1".
    echo Asegurate de que este archivo .bat y el archivo .ps1 esten juntos.
    pause
    exit /B
)

:: Reemplazamos los valores de Kiosco, Cliente y Sucursal en el codigo fuente y lo guardamos en C:
powershell -NoProfile -ExecutionPolicy Bypass -Command "$content = Get-Content -Path '%~dp0KioskNetMonitor_Supabase.ps1'; $content = $content -replace '\$KioskName\s*=.*', \"`$KioskName = '%KIOSCO%'\"; $content = $content -replace '\$ClientName\s*=.*', \"`$ClientName = '%CLIENTE%'\"; $content = $content -replace '\$Location\s*=.*', \"`$Location = '%SUCURSAL%'\"; $content | Set-Content -Path 'C:\KioskNetMonitor\KioskNetMonitor_Supabase.ps1'"

echo [3/3] Registrando e iniciando servicio invisible en Windows...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument '-ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:\KioskNetMonitor\KioskNetMonitor_Supabase.ps1\"'; $trigger = New-ScheduledTaskTrigger -AtStartup; $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Days 0); $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest; if (Get-ScheduledTask -TaskName 'Enlace360-NetMonitor' -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName 'Enlace360-NetMonitor' -Confirm:$false }; Register-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -TaskName 'Enlace360-NetMonitor' -Description 'Agente de Monitoreo de Red Enlace 360' | Out-Null; Start-ScheduledTask -TaskName 'Enlace360-NetMonitor'"

echo.
color 2F
echo ===================================================
echo   [OK] INSTALACION COMPLETADA CON EXITO
echo ===================================================
echo Equipo configurado: %KIOSCO%
echo Cliente configurado: %CLIENTE%
echo Sucursal configurada: %SUCURSAL%
echo.
echo El equipo ya esta siendo monitoreado de forma
echo 100%% invisible. Reportara al Dashboard 24/7.
echo.
echo Puedes borrar estos archivos del Escritorio.
echo Presiona cualquier tecla para salir...
pause >nul
exit /B
