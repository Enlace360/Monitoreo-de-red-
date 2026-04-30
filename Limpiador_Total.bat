@echo off
TITLE Limpiador Total - Enlace360
color 0C

:: Auto-elevar a Administrador
net session >nul 2>&1
if NOT %errorLevel% == 0 (
    echo Solicitando permisos de Administrador...
    powershell -Command "Start-Process -FilePath '%~dpnx0' -Verb RunAs"
    exit /b
)

echo =======================================================
echo   LIMPIEZA TOTAL DEL AGENTE ENLACE360
echo =======================================================
echo.

echo [1/4] Matando TODOS los procesos de PowerShell...
taskkill /F /IM powershell.exe >nul 2>&1
taskkill /F /IM pwsh.exe >nul 2>&1
echo       Hecho.

echo [2/4] Eliminando Tarea Programada "Enlace360_Agent"...
schtasks /Delete /TN "Enlace360_Agent" /F >nul 2>&1
echo       Hecho.

echo [3/4] Eliminando carpeta C:\KioskNetMonitor...
rmdir /S /Q "C:\KioskNetMonitor" >nul 2>&1
echo       Hecho.

echo [4/4] Limpiando carpeta shell:startup...
del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\*.bat" >nul 2>&1
del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\*.lnk" >nul 2>&1
echo       Hecho.

echo.
echo =======================================================
echo   LIMPIEZA COMPLETADA. El equipo esta virgen.
echo   Ahora puedes ejecutar el Instalador_Avanzado.bat
echo =======================================================
echo.
pause
