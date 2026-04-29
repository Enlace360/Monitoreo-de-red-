<#
.SYNOPSIS
    Instalador para el Kiosk Network Monitor.
.DESCRIPTION
    Copia los archivos a C:\KioskNetMonitor y crea una Tarea Programada 
    para que el script se ejecute automáticamente al iniciar el equipo.
#>

# Requiere permisos de administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Este script debe ejecutarse como Administrador."
    Pause
    exit
}

$InstallDir = "C:\KioskNetMonitor"
$SourceScript = Join-Path $PSScriptRoot "KioskNetMonitor.ps1"
$TargetScript = Join-Path $InstallDir "KioskNetMonitor.ps1"
$TaskName = "KioskNetworkMonitor"

# 1. Crear directorio
Write-Host "Creando directorio de instalación en $InstallDir..."
if (-not (Test-Path $InstallDir)) {
    New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
}

# 2. Copiar script
Write-Host "Copiando script principal..."
if (Test-Path $SourceScript) {
    Copy-Item -Path $SourceScript -Destination $TargetScript -Force
} else {
    Write-Error "No se encontró el script KioskNetMonitor.ps1 en el mismo directorio. Abortando."
    Pause
    exit
}

# 3. Crear Tarea Programada
Write-Host "Registrando Tarea Programada ($TaskName)..."
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$TargetScript`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Days 0) # Sin limite de tiempo
$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# Eliminar tarea si ya existe
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Register-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -TaskName $TaskName -Description "Monitorea la conexión de red en equipos Kiosco y envía alertas." | Out-Null

# 4. Iniciar Tarea
Write-Host "Iniciando servicio..."
Start-ScheduledTask -TaskName $TaskName

Write-Host "============================================="
Write-Host " INSTALACIÓN COMPLETADA EXITOSAMENTE " -ForegroundColor Green
Write-Host "============================================="
Write-Host "El monitor de red ya está corriendo en background."
Write-Host "Asegúrate de haber configurado los datos de correo en KioskNetMonitor.ps1 ANTES de instalar."
Pause
