@echo off
TITLE Diagnostico SYSTEM Enlace360
color 0B
setlocal EnableExtensions

set "SCRIPT=%~dp0Diagnosticar_Enlace360_SYSTEM.ps1"
set "INSTALL_DIR=C:\ProgramData\Enlace360\Agent"

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
echo ===== DIAGNOSTICO SYSTEM ENLACE360 =====
echo InstallDir: %INSTALL_DIR%
echo.
echo El diagnostico solo recolecta evidencia local por defecto.
echo Puede ejecutar el verificador final al terminar si quiere probar heartbeat/C2.
echo.
set "RUN_VERIFIER="
set /p "RUN_VERIFIER=Ejecutar verificador final al terminar? [N/s]: "
if /I "%RUN_VERIFIER%"=="S" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -InstallDir "%INSTALL_DIR%" -RunVerifier
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -InstallDir "%INSTALL_DIR%"
)

set "DIAG_EXIT=%errorLevel%"
echo.
if "%DIAG_EXIT%"=="0" (
    echo [PASS] Diagnostico generado.
) else (
    echo [FAIL] Diagnostico fallo.
)
echo.
pause
exit /b %DIAG_EXIT%
