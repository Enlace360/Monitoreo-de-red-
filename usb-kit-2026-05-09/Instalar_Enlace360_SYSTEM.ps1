param(
    [string]$InstallDir = "C:\ProgramData\Enlace360\Agent",
    [string]$ClientName = "Cenco Malls",
    [string]$Location = "Costanera",
    [string]$KioskName = "02 VTR - PB",
    [string]$AgentSecret = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$InstallerVersion = "SYSTEM-2026-05-10.1"
$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PreferredLogFile = "C:\Enlace360_SYSTEM_installer.log"
$LogFile = $PreferredLogFile
$TaskAgent = "Enlace360_Agent"
$TaskHealthCheck = "Enlace360_HealthCheck"
$ServiceName = "Enlace360Agent"
$ServiceExeName = "Enlace360Agent.exe"
$ServiceXmlName = "Enlace360Agent.xml"
$WinSWDownloadUrl = "https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe"
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

function New-AgentSecret {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
        return [Convert]::ToBase64String($bytes)
    } finally {
        $rng.Dispose()
    }
}

function Stop-DeleteTask {
    param([string]$TaskName)
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) { return }
    Log "Eliminando tarea previa $TaskName"
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

function Stop-AgentService {
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) { return }
    Log "Deteniendo servicio previo $ServiceName"
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
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

function Write-InstallStateSnapshot {
    param([string]$Stage)
    Log "===== ESTADO INSTALACION $Stage ====="
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) {
        Log ("Servicio {0}: Status={1}; StartType={2}" -f $ServiceName, $svc.Status, $svc.StartType)
    } else {
        Log ("Servicio {0}: NO EXISTE" -f $ServiceName)
    }

    foreach ($taskName in @($TaskAgent, $TaskHealthCheck, $TaskLegacyWatchdog, $TaskLegacyC2, $TaskLegacyPostBoot)) {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) {
            $info = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
            Log ("Tarea {0}: State={1}; User={2}; Last={3}" -f $taskName, $task.State, $task.Principal.UserId, $info.LastTaskResult)
        } else {
            Log ("Tarea {0}: NO EXISTE" -f $taskName)
        }
    }

    $procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        ($_.Name -eq "powershell.exe" -or $_.Name -eq "pwsh.exe") -and
        $_.CommandLine -match "Enlace360|Agente_Enlace360|KioskNetMonitor"
    })
    if ($procs.Count -eq 0) {
        Log "Procesos relacionados: ninguno"
    } else {
        foreach ($proc in $procs) {
            Log "Proceso relacionado PID=$($proc.ProcessId) Name=$($proc.Name) Cmd=$($proc.CommandLine)"
        }
    }
}

function Write-PathAclSnapshot {
    param(
        [string]$Title,
        [string]$Path
    )

    Log "===== $Title ====="
    if (-not (Test-Path -LiteralPath $Path)) {
        Log "No existe: $Path"
        return
    }

    try {
        $aclText = (Get-Acl -LiteralPath $Path | Format-List Path,Owner,AccessToString | Out-String -Width 220).Trim()
        foreach ($line in ($aclText -split "`r?`n")) {
            if (-not [string]::IsNullOrWhiteSpace($line)) { Log $line }
        }
    } catch {
        Log ("[WARN] No se pudo leer ACL de {0}: {1}" -f $Path, $_.Exception.Message)
    }
}

function Invoke-LoggedNativeCommand {
    param(
        [string]$Label,
        [string]$FilePath,
        [string[]]$Arguments
    )

    Log "Ejecutando $Label`: $FilePath $($Arguments -join ' ')"
    try {
        $output = & $FilePath @Arguments 2>&1
        foreach ($line in $output) {
            if (-not [string]::IsNullOrWhiteSpace([string]$line)) { Log "[$Label] $line" }
        }
        Log "$Label exit=$LASTEXITCODE"
    } catch {
        Log "[WARN] $Label fallo: $($_.Exception.Message)"
    }
}

function Repair-InstallDirectoryPermissions {
    if (-not (Test-Path -LiteralPath $InstallDir -PathType Container)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    Write-PathAclSnapshot -Title "ACL ANTES DE REPARAR PERMISOS" -Path $InstallDir

    Invoke-LoggedNativeCommand -Label "takeown" -FilePath "takeown.exe" -Arguments @("/F", $InstallDir, "/R", "/A", "/D", "Y")
    Invoke-LoggedNativeCommand -Label "attrib" -FilePath "attrib.exe" -Arguments @("-R", (Join-Path $InstallDir "*"), "/S", "/D")
    Invoke-LoggedNativeCommand -Label "icacls-reset" -FilePath "icacls.exe" -Arguments @($InstallDir, "/reset", "/T", "/C")

    icacls.exe $InstallDir /reset /T /C | Out-Null
    icacls.exe $InstallDir /inheritance:e /T /C | Out-Null
    icacls.exe $InstallDir /grant "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" /T /C | Out-Null

    Get-ChildItem -LiteralPath $InstallDir -Force -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            if (($_.Attributes -band [System.IO.FileAttributes]::ReadOnly) -eq [System.IO.FileAttributes]::ReadOnly) {
                $_.Attributes = ($_.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly))
            }
        } catch {
            Log ("[WARN] No se pudo quitar read-only a {0}: {1}" -f $_.FullName, $_.Exception.Message)
        }
    }

    Write-PathAclSnapshot -Title "ACL DESPUES DE REPARAR PERMISOS" -Path $InstallDir
}

function Write-RelatedProcessSnapshot {
    param([string]$Reason)
    Log "===== PROCESOS RELACIONADOS $Reason ====="
    $procs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        ($_.Name -match "powershell|pwsh|robocopy|cmd|conhost") -and
        ($_.CommandLine -match "Enlace360|Agente_Enlace360|ProgramData\\Enlace360|usb-kit|KioskNetMonitor")
    })
    if ($procs.Count -eq 0) {
        Log "Sin procesos relacionados visibles."
        return
    }
    foreach ($proc in $procs) {
        Log "PID=$($proc.ProcessId) Name=$($proc.Name) Cmd=$($proc.CommandLine)"
    }
}

function Write-CopyFailureDiagnostics {
    param(
        [string]$FileName,
        [string]$Stage,
        [string]$Source,
        [string]$Destination,
        [string]$ErrorText
    )

    Log "[ERROR] Fallo copiando $FileName etapa=$Stage"
    Log "[ERROR] Origen=$Source"
    Log "[ERROR] Destino=$Destination"
    Log "[ERROR] Detalle=$ErrorText"
    Write-PathAclSnapshot -Title "ACL DESTINO TRAS FALLA DE COPIA" -Path $InstallDir
    Write-RelatedProcessSnapshot -Reason "TRAS FALLA DE COPIA"
    Log "[RECOMENDACION] Si persiste ERROR 5 Acceso denegado: reinicia Windows y ejecuta Diagnosticar_Enlace360_SYSTEM.bat antes de reinstalar."
    Log "[RECOMENDACION] Reinicia Windows y ejecuta Diagnosticar_Enlace360_SYSTEM.bat si el bloqueo persiste."
}

function Copy-KitFileToStaging {
    param(
        [string]$Source,
        [string]$FileName,
        [string]$SourceHash
    )

    $StagingRoot = Join-Path $env:TEMP ("Enlace360_SYSTEM_stage_{0}" -f ([guid]::NewGuid().ToString("N")))
    New-Item -ItemType Directory -Path $StagingRoot -Force | Out-Null
    $staged = Join-Path $StagingRoot $FileName
    [System.IO.File]::Copy($Source, $staged, $true)
    $stagedHash = (Get-FileHash -LiteralPath $staged -Algorithm SHA256 -ErrorAction Stop).Hash
    if ($stagedHash -ne $SourceHash) {
        throw "Hash staging distinto para $FileName source=$SourceHash staging=$stagedHash"
    }
    Log "OK staging $FileName path=$staged hash=$stagedHash"
    return $staged
}

function Copy-KitFile {
    param(
        [string]$FileName,
        [string]$Label
    )

    $source = Join-Path $SourceDir $FileName
    $destination = Join-Path $InstallDir $FileName
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Falta archivo requerido: $source" }

    Log "Copiando $Label`: $source -> $destination"
    $sourceHash = $null
    try {
        $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256 -ErrorAction Stop).Hash
        Log "OK lectura origen $Label hash=$sourceHash"
    } catch {
        Write-CopyFailureDiagnostics -FileName $FileName -Stage "lectura_origen" -Source $source -Destination $destination -ErrorText $_.Exception.Message
        throw
    }

    $staged = $null
    try {
        $staged = Copy-KitFileToStaging -Source $source -FileName $FileName -SourceHash $sourceHash
    } catch {
        Write-CopyFailureDiagnostics -FileName $FileName -Stage "staging_temporal" -Source $source -Destination $destination -ErrorText $_.Exception.Message
        throw
    }

    try {
        [System.IO.File]::Copy($staged, $destination, $true)
    } catch {
        Write-CopyFailureDiagnostics -FileName $FileName -Stage "escritura_destino" -Source $source -Destination $destination -ErrorText $_.Exception.Message
        throw
    }

    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) { throw "No se copio $destination" }
    $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction Stop).Hash
    if ($hash -ne $sourceHash) { throw "Hash destino distinto para $FileName source=$sourceHash destino=$hash" }
    Log "OK copia $Label hash=$hash"
    return $destination
}

function New-SystemPowerShellAction {
    param([string]$ScriptPath)
    $args = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
    return New-ScheduledTaskAction -Execute "powershell.exe" -Argument $args -WorkingDirectory $InstallDir
}

function Write-ServiceWrapperConfig {
    param([string]$Path)
    $xml = @"
<service>
  <id>$ServiceName</id>
  <name>Enlace360 Agent</name>
  <description>Servicio principal Enlace360 para heartbeat, C2 e integridad.</description>
  <executable>powershell.exe</executable>
  <arguments>-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%BASE%\Agente_Enlace360_Service.ps1"</arguments>
  <workingdirectory>%BASE%</workingdirectory>
  <startmode>Automatic</startmode>
  <delayedAutoStart>true</delayedAutoStart>
  <onfailure action="restart" delay="10 sec"/>
  <onfailure action="restart" delay="30 sec"/>
  <onfailure action="restart" delay="60 sec"/>
  <logpath>%BASE%\service-logs</logpath>
  <log mode="roll-by-size">
    <sizeThreshold>1048576</sizeThreshold>
    <keepFiles>5</keepFiles>
  </log>
</service>
"@
    Write-TextFileUtf8 -Path $Path -Text $xml
}

function Ensure-ServiceWrapper {
    $serviceExe = Join-Path $InstallDir $ServiceExeName
    $sourceExe = Join-Path $SourceDir $ServiceExeName

    if (Test-Path -LiteralPath $sourceExe -PathType Leaf) {
        Copy-KitFile -FileName $ServiceExeName -Label "winsw wrapper" | Out-Null
        return $serviceExe
    }

    if (Test-Path -LiteralPath $serviceExe -PathType Leaf) { return $serviceExe }

    Log "Descargando WinSW para servicio Windows: $WinSWDownloadUrl"
    Invoke-WebRequest -Uri $WinSWDownloadUrl -OutFile $serviceExe -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
    return $serviceExe
}

function Install-AgentService {
    $serviceExe = Ensure-ServiceWrapper
    $serviceXml = Join-Path $InstallDir $ServiceXmlName
    Write-ServiceWrapperConfig -Path $serviceXml

    $existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($existing) {
        Log "Reinstalando servicio previo $ServiceName"
        & $serviceExe stop 2>&1 | ForEach-Object { Log "[winsw] $_" }
        & $serviceExe uninstall 2>&1 | ForEach-Object { Log "[winsw] $_" }
        Start-Sleep -Seconds 2
        sc.exe delete $ServiceName 2>&1 | Out-Null
        Start-Sleep -Seconds 2
    }

    Log "Instalando servicio Windows $ServiceName"
    & $serviceExe install 2>&1 | ForEach-Object { Log "[winsw] $_" }
    if ($LASTEXITCODE -ne 0) { throw "WinSW install fallo exit=$LASTEXITCODE" }

    sc.exe failure $ServiceName reset= 60 actions= restart/60000/restart/60000/restart/60000 2>&1 | Out-Null
    sc.exe failureflag $ServiceName 1 2>&1 | Out-Null

    Log "Arrancando servicio Windows $ServiceName"
    & $serviceExe start 2>&1 | ForEach-Object { Log "[winsw] $_" }
    if ($LASTEXITCODE -ne 0) { throw "WinSW start fallo exit=$LASTEXITCODE" }
}

function Write-TaskManifest {
    $manifest = [ordered]@{
        installer_version = $InstallerVersion
        install_dir = $InstallDir
        agent_cache = "agent_payload.cache"
        healthcheck_cache = "healthcheck_payload.cache"
        service = [ordered]@{
            name = $ServiceName
            wrapper = $ServiceExeName
            config = $ServiceXmlName
            start_mode = "Automatic"
        }
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
        -MultipleInstances Parallel
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
if ([string]::IsNullOrWhiteSpace($AgentSecret)) { $AgentSecret = New-AgentSecret }

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
$HealthCheckCachePath = Join-Path $InstallDir "healthcheck_payload.cache"
$VerifierPath = Join-Path $InstallDir "Verificar_Enlace360_SYSTEM.ps1"
$ConfigPath = Join-Path $InstallDir "config.json"

if (-not $DryRun) {
    Log "Deteniendo instalacion previa"
    Write-InstallStateSnapshot -Stage "ANTES_DETENER"
    Stop-AgentService
    foreach ($taskName in @($TaskAgent, $TaskHealthCheck, $TaskLegacyWatchdog, $TaskLegacyC2, $TaskLegacyPostBoot)) { Stop-DeleteTask -TaskName $taskName }
    Stop-EnlaceProcesses
    Write-InstallStateSnapshot -Stage "DESPUES_DETENER"
    Repair-InstallDirectoryPermissions
}

Log "Copiando archivos base del kit"
Copy-KitFile -FileName "Agente_Enlace360_Service.ps1" -Label "agente" | Out-Null
Log "Generando cache local del agente"
$agentCache = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($AgentSource))
$agentCache | Set-Content -LiteralPath $AgentCachePath -Encoding ASCII -Force
Log "OK cache local del agente"
Copy-KitFile -FileName "Verificar_Enlace360_SYSTEM.ps1" -Label "verificador" | Out-Null

Log "Escribiendo config"
@{
    ClientName = $ClientName
    Location = $Location
    KioskName = $KioskName
    AgentSecret = $AgentSecret
} | ConvertTo-Json | Set-Content -LiteralPath $ConfigPath -Encoding UTF8 -Force

Remove-Item -LiteralPath (Join-Path $InstallDir "c2.lock"),(Join-Path $InstallDir "last_heartbeat.txt"),(Join-Path $InstallDir "network_state.json") -Force -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath $InstallDir -Filter "*.dat" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

Log "Generando healthcheck"
$healthText = @'
$ErrorActionPreference = "Stop"
$InstallDir = Split-Path -Parent $PSCommandPath
$TaskName = "Enlace360_Agent"
$HealthTaskName = "Enlace360_HealthCheck"
$ServiceName = "Enlace360Agent"
$AgentPath = Join-Path $InstallDir "Agente_Enlace360_Service.ps1"
$AgentCachePath = Join-Path $InstallDir "agent_payload.cache"
$HealthCheckPath = Join-Path $InstallDir "Enlace360_HealthCheck.ps1"
$HealthCheckCachePath = Join-Path $InstallDir "healthcheck_payload.cache"
$ServiceExe = Join-Path $InstallDir "Enlace360Agent.exe"
$ServiceXml = Join-Path $InstallDir "Enlace360Agent.xml"
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
function Restore-HealthCheckFromCache {
    if (Test-Path -LiteralPath $HealthCheckPath -PathType Leaf) { return $true }
    if (-not (Test-Path -LiteralPath $HealthCheckCachePath -PathType Leaf)) {
        Add-HealthLog "[ERROR] Falta healthcheck y cache local: $HealthCheckPath / $HealthCheckCachePath"
        return $false
    }
    try {
        $payload = [System.IO.File]::ReadAllText($HealthCheckCachePath).Trim()
        $bytes = [Convert]::FromBase64String($payload)
        [System.IO.File]::WriteAllBytes($HealthCheckPath, $bytes)
        Add-HealthLog "HealthCheck restaurado desde cache local."
        return $true
    } catch {
        Add-HealthLog "[ERROR] No se pudo restaurar healthcheck desde cache: $($_.Exception.Message)"
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
function Ensure-AgentService {
    if (-not (Test-Path -LiteralPath $ServiceExe -PathType Leaf) -or -not (Test-Path -LiteralPath $ServiceXml -PathType Leaf)) {
        Add-HealthLog "Servicio $ServiceName no verificable: falta wrapper o XML."
        return $false
    }
    try {
        $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if (-not $svc) {
            Add-HealthLog "Servicio $ServiceName no existe. Instalando nuevamente."
            & $ServiceExe install 2>&1 | ForEach-Object { Add-HealthLog "[winsw] $_" }
            sc.exe failure $ServiceName reset= 60 actions= restart/60000/restart/60000/restart/60000 2>&1 | Out-Null
            sc.exe failureflag $ServiceName 1 2>&1 | Out-Null
            Start-Sleep -Seconds 2
            $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        }
        if ($svc -and $svc.Status -ne "Running") {
            Add-HealthLog "Servicio $ServiceName esta $($svc.Status). Arrancando."
            & $ServiceExe start 2>&1 | ForEach-Object { Add-HealthLog "[winsw] $_" }
            Start-Sleep -Seconds 5
        }
        return ((Get-Service -Name $ServiceName -ErrorAction SilentlyContinue).Status -eq "Running")
    } catch {
        Add-HealthLog ("[ERROR] No se pudo asegurar servicio {0}: {1}" -f $ServiceName, $_.Exception.Message)
        return $false
    }
}
try {
    Restore-AgentFromCache | Out-Null
    Restore-HealthCheckFromCache | Out-Null
    Ensure-AgentTask
    $serviceOk = Ensure-AgentService
    $proc = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        ($_.Name -eq "powershell.exe" -or $_.Name -eq "pwsh.exe") -and
        $_.CommandLine -like "*Agente_Enlace360_Service.ps1*"
    })
    if ($proc.Count -lt 1 -and $serviceOk) {
        Start-Sleep -Seconds 5
        $proc = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            ($_.Name -eq "powershell.exe" -or $_.Name -eq "pwsh.exe") -and
            $_.CommandLine -like "*Agente_Enlace360_Service.ps1*"
        })
    }
    if ($proc.Count -lt 1) {
        Add-HealthLog "Agente no detectado. Arrancando tarea principal de respaldo."
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    }
} catch {
    Add-HealthLog "[ERROR] $($_.Exception.Message)"
}
'@
Write-TextFileUtf8 -Path $HealthCheckPath -Text $healthText
$healthCache = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($HealthCheckPath))
$healthCache | Set-Content -LiteralPath $HealthCheckCachePath -Encoding ASCII -Force

Log "Escribiendo manifiesto"
Write-TaskManifest

if ($DryRun) {
    Log "DRY RUN completo. No se registraron tareas."
    exit 0
}

Log "Registrando tareas SYSTEM"
Register-SystemTasks

Log "Instalando servicio Windows principal"
Install-AgentService

Log "Arrancando HealthCheck de respaldo"
Start-ScheduledTask -TaskName $TaskHealthCheck -ErrorAction SilentlyContinue
Wait-Until -Label "proceso agente vivo" -TimeoutSeconds 80 -Condition { @(Get-AgentProcess).Count -gt 0 }

Log "Validacion rapida con verificador SYSTEM"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $VerifierPath -InstallDir $InstallDir -ObserveSeconds 0
if ($LASTEXITCODE -ne 0) { throw "Verificador SYSTEM fallo con exit=$LASTEXITCODE" }

Log "===== PASS INSTALADOR SYSTEM ENLACE360 ====="
exit 0
