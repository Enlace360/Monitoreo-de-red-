@echo off
TITLE AutoTest SYSTEM Enlace360 - Codex
color 0B
setlocal EnableExtensions

set "SCRIPT=%~dp0AutoTest_Enlace360_SYSTEM.ps1"
set "INSTALL_DIR=C:\ProgramData\Enlace360\Agent"
set "CLIENT_NAME=%~1"
set "LOCATION=%~2"
set "KIOSK_NAME=%~3"
set "OBSERVE_SECONDS=180"
set "EXTRA_ARGS="

if not defined CLIENT_NAME set "CLIENT_NAME=Cenco Malls"
if not defined LOCATION set "LOCATION=Costanera"
if not defined KIOSK_NAME set "KIOSK_NAME=%COMPUTERNAME%"

if /I "%~4"=="AUTO_REBOOT" set "EXTRA_ARGS=%EXTRA_ARGS% -AutoReboot"
if /I "%~4"=="SKIP_INSTALL" set "EXTRA_ARGS=%EXTRA_ARGS% -SkipInstall"
if /I "%~4"=="POST_REBOOT" set "EXTRA_ARGS=%EXTRA_ARGS% -PostReboot -SkipInstall"
if /I "%~5"=="AUTO_REBOOT" set "EXTRA_ARGS=%EXTRA_ARGS% -AutoReboot"
if /I "%~5"=="SKIP_INSTALL" set "EXTRA_ARGS=%EXTRA_ARGS% -SkipInstall"
if /I "%~5"=="POST_REBOOT" set "EXTRA_ARGS=%EXTRA_ARGS% -PostReboot -SkipInstall"

net session >nul 2>&1
if NOT %errorLevel% == 0 (
    echo Solicitando permisos de Administrador...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~dpnx0' -ArgumentList '\"%CLIENT_NAME%\" \"%LOCATION%\" \"%KIOSK_NAME%\" %~4 %~5' -Verb RunAs"
    exit /b
)

if not exist "%SCRIPT%" (
    echo [ERROR] No encuentro "%SCRIPT%".
    exit /b 1
)

echo ===== AUTOTEST SYSTEM ENLACE360 CODEX =====
echo Cliente:    %CLIENT_NAME%
echo Ubicacion:  %LOCATION%
echo Kiosco:     %KIOSK_NAME%
echo Log:        C:\Enlace360_SYSTEM_autotest.log
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -InstallDir "%INSTALL_DIR%" -ClientName "%CLIENT_NAME%" -Location "%LOCATION%" -KioskName "%KIOSK_NAME%" -ObserveSeconds %OBSERVE_SECONDS% %EXTRA_ARGS%
exit /b %errorLevel%
