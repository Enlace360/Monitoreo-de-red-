param(
    [string]$InstallDir = "C:\ProgramData\Enlace360\Agent",
    [string]$ClientName = "Cenco Malls",
    [string]$Location = "Costanera",
    [string]$KioskName = "02 VTR - PB",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$InstallerVersion = "SYSTEM-2026-05-01.5"
$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PreferredLogFile = "C:\Enlace360_SYSTEM_installer.log"
$LogFile = $PreferredLogFile
$TaskAgent = "Enlace360_Agent"
$TaskHealthCheck = "Enlace360_HealthCheck"
$TaskLegacyWatchdog = "Enlace360_Agent_Watchdog"
$TaskLegacyC2 = "Enlace360_Agent_C2"
$TaskLegacyPostBoot = "Enlace360_PostBoot_Validation"

try {
    "" | Out-File -FilePath $LogFile -Force -Encoding UTF8 -ErrorAction Stop
    Remove-Item -LiteralPath $LogFile -Force -ErrorAction SilentlyContinue
} catch {
    $LogFile = Join-Path $env:TEMP "Enlace360_SYSTEM_installer.log"
    Remove-Item -LiteralPath $LogFile -Force -ErrorAction SilentlyContinue
}

function Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    $line | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Ejecuta este instalador como Administrador."
    }
}

function Write-TextFileUtf8 {
    param([string]$Path, [string]$Text)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Stop-DeleteTask {
    param([string]$TaskName)
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) { return }
    Log "Eliminando tarea previa $TaskName"
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

function Stop-EnlaceProcesses {
    $currentPid = $PID
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessId -ne $currentPid -and
            ($_.Name -eq "powershell.exe" -or $_.Name -eq "pwsh.exe") -and
            $_.CommandLine -match "Enlace360|KioskNetMonitor|Agente_Enlace360_Service"
        } |
        ForEach-Object {
            Log "Deteniendo PID $($_.ProcessId) $($_.Name)"
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
}

function New-SystemPowerShellAction {
    param([string]$ScriptPath)
    $args = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
    return New-ScheduledTaskAction -Execute "powershell.exe" -Argument $args -WorkingDirectory $InstallDir
}

function Write-TaskManifest {
    $manifest = [ordered]@{
        installer_version = $InstallerVersion
        install_dir = $InstallDir
        agent_cache = "agent_payload.cache"
        tasks = @(
            [ordered]@{
                name = $TaskAgent
                user = "SYSTEM"
                triggers = @("AtStartup", "AtLogOn")
                action = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$AgentPath`""
            },
            [ordered]@{
                name = $TaskHealthCheck
                user = "SYSTEM"
                triggers = @("AtStartup", "EveryFiveMinutes")
                action = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$HealthCheckPath`""
            }
        )
    }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $InstallDir "install_manifest.json") -Encoding UTF8 -Force
}

function Register-SystemTasks {
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    $agentAction = New-SystemPowerShellAction -ScriptPath $AgentPath
    $agentSettings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -DontStopOnIdleEnd `
        -ExecutionTimeLimit (New-TimeSpan -Days 0) `
        -RestartCount 999 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $TaskAgent -Action $agentAction -Trigger @(
        New-ScheduledTaskTrigger -AtStartup
        New-ScheduledTaskTrigger -AtLogOn
    ) -Principal $principal -Settings $agentSettings -Description "Enlace360 agent heartbeat y C2 como SYSTEM" -Force | Out-Null

    $healthAction = New-SystemPowerShellAction -ScriptPath $HealthCheckPath
    $healthSettings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -DontStopOnIdleEnd `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
        -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $TaskHealthCheck -Action $healthAction -Trigger @(
        New-ScheduledTaskTrigger -AtStartup
        New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
    ) -Principal $principal -Settings $healthSettings -Description "Enlace360 healthcheck minimo como SYSTEM" -Force | Out-Null
}

function Wait-Until {
    param(
        [string]$Label,
        [scriptblock]$Condition,
        [int]$TimeoutSeconds = 60,
        [int]$IntervalSeconds = 2
    )
    Log "Esperando: $Label"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (& $Condition) {
            Log "OK: $Label"
            return
        }
        Start-Sleep -Seconds $IntervalSeconds
    } while ((Get-Date) -lt $deadline)
    throw "Timeout esperando: $Label"
}

function Get-AgentProcess {
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        ($_.Name -eq "powershell.exe" -or $_.Name -eq "pwsh.exe") -and
        $_.CommandLine -like "*Agente_Enlace360_Service.ps1*"
    })
}

Log "===== INSTALADOR SYSTEM ENLACE360 ====="
Log "InstallerVersion=$InstallerVersion"
Log "InstallDir=$InstallDir"
Log "SourceDir=$SourceDir"
Log "DryRun=$DryRun"

if (-not $DryRun) { Assert-Admin }

$AgentSource = Join-Path $SourceDir "Agente_Enlace360_Service.ps1"
$VerifierSource = Join-Path $SourceDir "Verificar_Enlace360_SYSTEM.ps1"
foreach ($required in @($AgentSource, $VerifierSource)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Falta archivo requerido: $required" }
}

Log "Preparando carpeta destino"
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
if (-not $DryRun) {
    icacls.exe $InstallDir /inheritance:e /T /C | Out-Null
    icacls.exe $InstallDir /grant "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" /T /C | Out-Null
}

$AgentPath = Join-Path $InstallDir "Agente_Enlace360_Service.ps1"
$AgentCachePath = Join-Path $InstallDir "agent_payload.cache"
$HealthCheckPath = Join-Path $InstallDir "Enlace360_HealthCheck.ps1"
$VerifierPath = Join-Path $InstallDir "Verificar_Enlace360_SYSTEM.ps1"
$ConfigPath = Join-Path $InstallDir "config.json"

if (-not $DryRun) {
    Log "Deteniendo instalacion previa"
    foreach ($taskName in @($TaskAgent, $TaskHealthCheck, $TaskLegacyWatchdog, $TaskLegacyC2, $TaskLegacyPostBoot)) { Stop-DeleteTask -TaskName $taskName }
    Stop-EnlaceProcesses
}

Log "Copiando agente y verificador"
Copy-Item -LiteralPath $AgentSource -Destination $AgentPath -Force
$agentCache = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($AgentSource))
$agentCache | Set-Content -LiteralPath $AgentCachePath -Encoding ASCII -Force
Copy-Item -LiteralPath $VerifierSource -Destination $VerifierPath -Force

Log "Escribiendo config"
@{
    ClientName = $ClientName
    Location = $Location
    KioskName = $KioskName
} | ConvertTo-Json | Set-Content -LiteralPath $ConfigPath -Encoding UTF8 -Force

Remove-Item -LiteralPath (Join-Path $InstallDir "c2.lock"),(Join-Path $InstallDir "last_heartbeat.txt"),(Join-Path $InstallDir "network_state.json") -Force -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath $InstallDir -Filter "*.dat" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

Log "Generando healthcheck"
$healthText = @'
$ErrorActionPreference = "Stop"
$InstallDir = Split-Path -Parent $PSCommandPath
$TaskName = "Enlace360_Agent"
$AgentPath = Join-Path $InstallDir "Agente_Enlace360_Service.ps1"
$AgentCachePath = Join-Path $InstallDir "agent_payload.cache"
$LogFile = Join-Path $InstallDir "healthcheck.log"
function Add-HealthLog([string]$Message) {
    ("[{0}] {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Message) | Out-File -FilePath $LogFile -Append -Encoding UTF8
}
function Restore-AgentFromCache {
    if (Test-Path -LiteralPath $AgentPath -PathType Leaf) { return $true }
    if (-not (Test-Path -LiteralPath $AgentCachePath -PathType Leaf)) {
        Add-HealthLog "[ERROR] Falta agente y cache local: $AgentPath / $AgentCachePath"
        return $false
    }
    try {
        $payload = [System.IO.File]::ReadAllText($AgentCachePath).Trim()
        $bytes = [Convert]::FromBase64String($payload)
        [System.IO.File]::WriteAllBytes($AgentPath, $bytes)
        Add-HealthLog "Agente restaurado desde cache local."
        return $true
    } catch {
        Add-HealthLog "[ERROR] No se pudo restaurar agente desde cache: $($_.Exception.Message)"
        return $false
    }
}
function New-SystemPowerShellActionLocal([string]$ScriptPath) {
    $args = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
    return New-ScheduledTaskAction -Execute "powershell.exe" -Argument $args -WorkingDirectory $InstallDir
}
function Ensure-AgentTask {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) { return }
    Add-HealthLog "Tarea $TaskName no existe. Registrando nuevamente."
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Days 0) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $TaskName -Action (New-SystemPowerShellActionLocal $AgentPath) -Trigger @(
        New-ScheduledTaskTrigger -AtStartup
        New-ScheduledTaskTrigger -AtLogOn
    ) -Principal $principal -Settings $settings -Description "Enlace360 agent heartbeat y C2 como SYSTEM" -Force | Out-Null
}
try {
    Restore-AgentFromCache | Out-Null
    Ensure-AgentTask
    $proc = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        ($_.Name -eq "powershell.exe" -or $_.Name -eq "pwsh.exe") -and
        $_.CommandLine -like "*Agente_Enlace360_Service.ps1*"
    })
    if ($proc.Count -lt 1) {
        Add-HealthLog "Agente no detectado. Arrancando tarea principal."
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    }
} catch {
    Add-HealthLog "[ERROR] $($_.Exception.Message)"
}
'@
Write-TextFileUtf8 -Path $HealthCheckPath -Text $healthText

Log "Escribiendo manifiesto"
Write-TaskManifest

if ($DryRun) {
    Log "DRY RUN completo. No se registraron tareas."
    exit 0
}

Log "Registrando tareas SYSTEM"
Register-SystemTasks

Log "Arrancando agente"
Start-ScheduledTask -TaskName $TaskAgent
Wait-Until -Label "proceso agente vivo" -TimeoutSeconds 80 -Condition { @(Get-AgentProcess).Count -gt 0 }

Log "Validacion rapida con verificador SYSTEM"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $VerifierPath -InstallDir $InstallDir -ObserveSeconds 0
if ($LASTEXITCODE -ne 0) { throw "Verificador SYSTEM fallo con exit=$LASTEXITCODE" }

Log "===== PASS INSTALADOR SYSTEM ENLACE360 ====="
exit 0
