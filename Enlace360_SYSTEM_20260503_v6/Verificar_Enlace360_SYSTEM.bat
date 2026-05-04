@echo off
TITLE Verificador SYSTEM Enlace360
color 0B
setlocal EnableExtensions

set "SCRIPT=%~dp0Verificar_Enlace360_SYSTEM.ps1"
set "INSTALL_DIR=C:\ProgramData\Enlace360\Agent"
set "OBSERVE_SECONDS=150"

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
echo ===== VERIFICADOR SYSTEM ENLACE360 =====
echo InstallDir: %INSTALL_DIR%
echo Log:        C:\Enlace360_SYSTEM_verifier.log
echo Observacion heartbeat/dashboard: %OBSERVE_SECONDS% segundos
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -InstallDir "%INSTALL_DIR%" -ObserveSeconds %OBSERVE_SECONDS% -TestHealthCheck
set "VERIFY_EXIT=%errorLevel%"

echo.
if "%VERIFY_EXIT%"=="0" (
    echo [PASS] Verificacion SYSTEM completada.
) else (
    echo [FAIL] Verificacion SYSTEM fallo. Revisa C:\Enlace360_SYSTEM_verifier.log
)
echo.
pause
exit /b %VERIFY_EXIT%
