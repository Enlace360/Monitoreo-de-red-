@echo off
TITLE Instalador SYSTEM Enlace360
color 0B
setlocal EnableExtensions

set "SCRIPT=%~dp0Instalar_Enlace360_SYSTEM.ps1"
set "INSTALL_DIR=C:\ProgramData\Enlace360\Agent"
set "DEFAULT_CLIENT_NAME=Cenco Malls"
set "DEFAULT_LOCATION=Costanera"
set "DEFAULT_KIOSK_NAME=%COMPUTERNAME%"

net session >nul 2>&1
if NOT %errorLevel% == 0 (
    echo Solicitando permisos de Administrador...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~dpnx0' -Verb RunAs"
    exit /b
)

if not exist "%SCRIPT%" (
    echo [ERROR] No encuentro "%SCRIPT%".
    echo Mantenga este BAT junto al PS1 en la misma carpeta.
    pause
    exit /b 1
)

echo.
echo ===== INSTALADOR SYSTEM ENLACE360 =====
echo Complete los datos del equipo. Presione Enter para usar el valor entre corchetes.
echo.
set /p "CLIENT_NAME=Cliente [%DEFAULT_CLIENT_NAME%]: "
if not defined CLIENT_NAME set "CLIENT_NAME=%DEFAULT_CLIENT_NAME%"
set /p "LOCATION=Ubicacion/Sucursal [%DEFAULT_LOCATION%]: "
if not defined LOCATION set "LOCATION=%DEFAULT_LOCATION%"
set /p "KIOSK_NAME=PC/Kiosco [%DEFAULT_KIOSK_NAME%]: "
if not defined KIOSK_NAME set "KIOSK_NAME=%DEFAULT_KIOSK_NAME%"
echo.
echo InstallDir: %INSTALL_DIR%
echo Cliente:    %CLIENT_NAME%
echo Ubicacion:  %LOCATION%
echo Kiosco:     %KIOSK_NAME%
echo Log:        C:\Enlace360_SYSTEM_installer.log
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -InstallDir "%INSTALL_DIR%" -ClientName "%CLIENT_NAME%" -Location "%LOCATION%" -KioskName "%KIOSK_NAME%"
set "INSTALL_EXIT=%errorLevel%"

echo.
if "%INSTALL_EXIT%"=="0" (
    echo [PASS] Instalacion SYSTEM completada.
) else (
    echo [FAIL] Instalacion SYSTEM fallo. Revisa C:\Enlace360_SYSTEM_installer.log
)
echo.
pause
exit /b %INSTALL_EXIT%
