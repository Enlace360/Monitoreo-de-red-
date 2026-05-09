@echo off
TITLE AutoTest SYSTEM Enlace360
color 0B
setlocal EnableExtensions

set "SCRIPT=%~dp0AutoTest_Enlace360_SYSTEM.ps1"
set "INSTALL_DIR=C:\ProgramData\Enlace360\Agent"
set "DEFAULT_CLIENT_NAME=Cenco Malls"
set "DEFAULT_LOCATION=Costanera"
set "DEFAULT_KIOSK_NAME=%COMPUTERNAME%"
set "OBSERVE_SECONDS=180"

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
echo ===== AUTOTEST SYSTEM ENLACE360 =====
echo Este flujo automatiza instalacion, verificacion, evidencia y post-reinicio.
echo Log: C:\Enlace360_SYSTEM_autotest.log
echo.
set /p "CLIENT_NAME=Cliente [%DEFAULT_CLIENT_NAME%]: "
if not defined CLIENT_NAME set "CLIENT_NAME=%DEFAULT_CLIENT_NAME%"
set /p "LOCATION=Ubicacion/Sucursal [%DEFAULT_LOCATION%]: "
if not defined LOCATION set "LOCATION=%DEFAULT_LOCATION%"
set /p "KIOSK_NAME=PC/Kiosco [%DEFAULT_KIOSK_NAME%]: "
if not defined KIOSK_NAME set "KIOSK_NAME=%DEFAULT_KIOSK_NAME%"
echo.
echo Modo:
echo   1 = Instalar + verificar + dejar tarea post-reinicio
echo   2 = Solo verificar instalacion existente
echo   3 = Continuar post-reinicio ahora
set /p "MODE=Seleccione modo [1]: "
if not defined MODE set "MODE=1"
set "EXTRA_ARGS="
if "%MODE%"=="2" set "EXTRA_ARGS=%EXTRA_ARGS% -SkipInstall"
if "%MODE%"=="3" set "EXTRA_ARGS=%EXTRA_ARGS% -PostReboot"
echo.
set /p "REBOOT_NOW=Reiniciar automaticamente al terminar instalacion? [N]: "
if /I "%REBOOT_NOW%"=="S" set "EXTRA_ARGS=%EXTRA_ARGS% -AutoReboot"
if /I "%REBOOT_NOW%"=="Y" set "EXTRA_ARGS=%EXTRA_ARGS% -AutoReboot"
echo.
echo InstallDir: %INSTALL_DIR%
echo Cliente:    %CLIENT_NAME%
echo Ubicacion:  %LOCATION%
echo Kiosco:     %KIOSK_NAME%
echo Observacion: %OBSERVE_SECONDS% segundos
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -InstallDir "%INSTALL_DIR%" -ClientName "%CLIENT_NAME%" -Location "%LOCATION%" -KioskName "%KIOSK_NAME%" -ObserveSeconds %OBSERVE_SECONDS% %EXTRA_ARGS%
set "AUTO_EXIT=%errorLevel%"

echo.
if "%AUTO_EXIT%"=="0" (
    echo [PASS] AutoTest SYSTEM completado. Revisa C:\Enlace360_SYSTEM_autotest.log
) else (
    echo [FAIL] AutoTest SYSTEM fallo. Revisa C:\Enlace360_SYSTEM_autotest.log
)
echo.
pause
exit /b %AUTO_EXIT%
