param(
    [string]$InstallDir = "C:\ProgramData\Enlace360\Agent",
    [int]$AgentLogTail = 160,
    [int]$HealthLogTail = 120,
    [int]$C2LogTail = 120,
    [int]$EventMax = 80,
    [int]$ForensicDays = 14,
    [int]$EventScanMax = 5000,
    [switch]$RunVerifier,
    [int]$VerifierObserveSeconds = 0
)

$ErrorActionPreference = "Continue"
$DiagnosticVersion = "SYSTEM-DIAG-2026-05-06.1"
$TaskAgent = "Enlace360_Agent"
$TaskHealthCheck = "Enlace360_HealthCheck"
$ServiceName = "Enlace360Agent"
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OutDir = "C:\Enlace360_SYSTEM_Diagnostico_$Stamp"
$ReportPath = Join-Path $OutDir "diagnostico.txt"
$ZipPath = "$OutDir.zip"
$ForensicStart = (Get-Date).AddDays(-1 * $ForensicDays)

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

function Add-Line {
    param([string]$Text = "")
    $Text | Out-File -FilePath $ReportPath -Append -Encoding UTF8
    Write-Host $Text
}

function Add-Section {
    param([string]$Title)
    Add-Line ""
    Add-Line ("===== {0} =====" -f $Title)
}

function Invoke-CaptureBlock {
    param(
        [string]$Title,
        [scriptblock]$Body
    )

    Add-Section $Title
    try {
        $output = & $Body 2>&1
        if ($null -eq $output) {
            Add-Line "(sin salida)"
            return
        }
        $output | Out-String -Width 240 | ForEach-Object {
            $_.TrimEnd() -split "`r?`n" | ForEach-Object { Add-Line $_ }
        }
    } catch {
        Add-Line ("[ERROR] {0}" -f $_.Exception.Message)
    }
}

function Invoke-CaptureCommand {
    param(
        [string]$Title,
        [string]$FilePath,
        [string[]]$Arguments = @()
    )

    Add-Section $Title
    Add-Line ("> {0} {1}" -f $FilePath, ($Arguments -join " "))
    try {
        $output = & $FilePath @Arguments 2>&1
        if ($null -eq $output) {
            Add-Line "(sin salida)"
            return
        }
        $output | Out-String -Width 240 | ForEach-Object {
            $_.TrimEnd() -split "`r?`n" | ForEach-Object { Add-Line $_ }
        }
    } catch {
        Add-Line ("[ERROR] {0}" -f $_.Exception.Message)
    }
}

function Copy-EvidenceFile {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Copy-Item -LiteralPath $Path -Destination (Join-Path $OutDir (Split-Path $Path -Leaf)) -Force -ErrorAction SilentlyContinue
    }
}

function Copy-EvidenceDirectory {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $dest = Join-Path $OutDir (Split-Path $Path -Leaf)
        Copy-Item -LiteralPath $Path -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Read-SupabaseCredentials {
    param(
        [string]$AgentPath,
        [string]$AgentCachePath = (Join-Path (Split-Path -Parent $AgentPath) "agent_payload.cache")
    )

    $source = $null
    $sourceLabel = $null
    if (Test-Path -LiteralPath $AgentPath -PathType Leaf) {
        $source = Get-Content -LiteralPath $AgentPath -Raw -ErrorAction Stop
        $sourceLabel = $AgentPath
    } elseif (Test-Path -LiteralPath $AgentCachePath -PathType Leaf) {
        $payload = [System.IO.File]::ReadAllText($AgentCachePath).Trim()
        $bytes = [Convert]::FromBase64String($payload)
        $source = [System.Text.Encoding]::UTF8.GetString($bytes)
        $sourceLabel = $AgentCachePath
    } else {
        throw "No existe agente ni agent_payload.cache para leer credenciales Supabase."
    }

    $url = [regex]::Match($source, '\$SupabaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
    $key = [regex]::Match($source, '\$SupabaseAnonKey\s*=\s*"([^"]+)"').Groups[1].Value
    if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($key)) {
        throw "No pude leer credenciales Supabase desde $sourceLabel"
    }
    return @{
        Url = $url
        Key = $key
        Source = $sourceLabel
        Headers = @{
            apikey = $key
            Authorization = "Bearer $key"
        }
    }
}

function Invoke-SupabaseJson {
    param(
        [string]$Uri,
        [hashtable]$Headers,
        [string]$Method = "GET",
        [object]$Body = $null
    )
    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 6
        return Invoke-RestMethod -Uri $Uri -Method $Method -Headers $Headers -Body $json -ContentType "application/json; charset=utf-8" -TimeoutSec 20 -ErrorAction Stop
    }
    Invoke-RestMethod -Uri $Uri -Method $Method -Headers $Headers -TimeoutSec 20 -ErrorAction Stop
}

function Get-C2AdminSecret {
    if ([string]::IsNullOrWhiteSpace($env:ENLACE360_C2_ADMIN_SECRET)) { return "" }
    return [string]$env:ENLACE360_C2_ADMIN_SECRET
}

function Get-AgentProcess {
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        ($_.Name -eq "powershell.exe" -or $_.Name -eq "pwsh.exe") -and
        $_.CommandLine -like "*Agente_Enlace360_Service.ps1*"
    })
}

function Get-LocalState {
    $statePath = Join-Path $InstallDir "network_state.json"
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $null }
    try { return Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { return $null }
}

function Select-EventSummary {
    process {
        [pscustomobject]@{
            TimeCreated = $_.TimeCreated
            Id = $_.Id
            ProviderName = $_.ProviderName
            Level = $_.LevelDisplayName
            Message = (($_.Message -replace "`r?`n", " ") -replace "\s{2,}", " ").Trim()
        }
    }
}

function Add-DiagnosticSummary {
    Add-Section "RESUMEN AUTOMATICO"
    $agentPath = Join-Path $InstallDir "Agente_Enlace360_Service.ps1"
    $configPath = Join-Path $InstallDir "config.json"
    $agentLog = Join-Path $InstallDir "agente.log"
    $agentTask = Get-ScheduledTask -TaskName $TaskAgent -ErrorAction SilentlyContinue
    $healthTask = Get-ScheduledTask -TaskName $TaskHealthCheck -ErrorAction SilentlyContinue
    $agentInfo = Get-ScheduledTaskInfo -TaskName $TaskAgent -ErrorAction SilentlyContinue
    $healthInfo = Get-ScheduledTaskInfo -TaskName $TaskHealthCheck -ErrorAction SilentlyContinue
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    $serviceInfo = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $ServiceName) -ErrorAction SilentlyContinue
    $agentProc = @(Get-AgentProcess)
    $state = Get-LocalState
    $integrityPath = Join-Path $InstallDir "integrity_state.json"

    Add-Line ("InstallDir existe: {0}" -f (Test-Path -LiteralPath $InstallDir -PathType Container))
    Add-Line ("Agente instalado: {0}" -f (Test-Path -LiteralPath $agentPath -PathType Leaf))
    Add-Line ("Config instalada: {0}" -f (Test-Path -LiteralPath $configPath -PathType Leaf))
    Add-Line ("Proceso agente vivo: {0}" -f ($agentProc.Count -gt 0))
    if ($agentProc.Count -gt 0) { Add-Line ("PID agente: {0}" -f (($agentProc | Select-Object -ExpandProperty ProcessId) -join ",")) }
    if ($service) { Add-Line ("Servicio {0}: Status={1}; StartMode={2}" -f $ServiceName, $service.Status, $serviceInfo.StartMode) } else { Add-Line ("Servicio {0}: NO EXISTE" -f $ServiceName) }
    if ($agentTask) { Add-Line ("Tarea {0}: State={1}; Last={2}" -f $TaskAgent, $agentTask.State, $agentInfo.LastTaskResult) } else { Add-Line ("Tarea {0}: NO EXISTE" -f $TaskAgent) }
    if ($healthTask) { Add-Line ("Tarea {0}: State={1}; Last={2}" -f $TaskHealthCheck, $healthTask.State, $healthInfo.LastTaskResult) } else { Add-Line ("Tarea {0}: NO EXISTE" -f $TaskHealthCheck) }
    if (Test-Path -LiteralPath $agentLog -PathType Leaf) {
        $lastWrite = (Get-Item -LiteralPath $agentLog).LastWriteTime
        Add-Line ("Ultimo agente.log: {0}" -f $lastWrite.ToString("yyyy-MM-dd HH:mm:ss"))
    }
    if ($state) {
        Add-Line ("network_state.json Status: {0}" -f $state.Status)
        Add-Line ("network_state.json OfflineTime: {0}" -f $state.OfflineTime)
    } else {
        Add-Line "network_state.json: no existe o no parsea"
    }
    if (Test-Path -LiteralPath $integrityPath -PathType Leaf) {
        try {
            $integrity = Get-Content -LiteralPath $integrityPath -Raw | ConvertFrom-Json
            Add-Line ("integrity_state.json: status={0}; alert={1}" -f $integrity.status, $integrity.alert)
        } catch {
            Add-Line "integrity_state.json: existe pero no parsea"
        }
    } else {
        Add-Line "integrity_state.json: no existe"
    }

    if (-not $service -and -not $agentTask -and -not $healthTask) {
        Add-Line "Diagnostico probable: SERVICIO Y TAREAS AUSENTES. Revisar secciones FORENSE para confirmar si hubo borrado manual, C2, EDR o politica."
    } elseif (-not $agentTask -and -not $healthTask) {
        Add-Line "Diagnostico probable: TAREAS SYSTEM AUSENTES. Revisar secciones FORENSE para confirmar si hubo borrado manual, C2, EDR o politica."
    } elseif (-not (Test-Path -LiteralPath $InstallDir -PathType Container)) {
        Add-Line "Diagnostico probable: AGENTE NO INSTALADO EN ESTA RUTA."
    } elseif ($agentProc.Count -lt 1 -and $agentTask) {
        Add-Line "Diagnostico probable: Windows esta vivo, pero el agente no tiene proceso. Revisar HealthCheck y LastTaskResult."
    } elseif ($state -and $state.Status -eq "OFFLINE") {
        Add-Line "Diagnostico probable: el agente detecto falla real de red y dejo estado OFFLINE local."
    } elseif ($agentProc.Count -gt 0) {
        Add-Line "Diagnostico probable: agente vivo. Si dashboard esta offline, comparar heartbeat Supabase contra logs y conectividad."
    } else {
        Add-Line "Diagnostico probable: revisar eventos de energia/red y logs copiados en este paquete."
    }
}

Add-Line "===== DIAGNOSTICO SYSTEM ENLACE360 ====="
Add-Line ("DiagnosticVersion={0}" -f $DiagnosticVersion)
Add-Line ("FechaLocal={0}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
Add-Line ("Equipo={0}" -f $env:COMPUTERNAME)
Add-Line ("Usuario={0}\{1}" -f $env:USERDOMAIN, $env:USERNAME)
Add-Line ("InstallDir={0}" -f $InstallDir)
Add-Line ("OutDir={0}" -f $OutDir)
Add-Line ("RunVerifier={0}" -f $RunVerifier)
Add-Line ("ForensicStart={0}" -f $ForensicStart.ToString("yyyy-MM-dd HH:mm:ss"))

Add-DiagnosticSummary

Invoke-CaptureBlock "ARCHIVOS INSTALADOS" {
    Get-ChildItem C:\ProgramData\Enlace360\Agent -Force
}

Invoke-CaptureBlock "TAREAS PROGRAMADAS" {
    Get-ScheduledTask Enlace360_Agent,Enlace360_HealthCheck | Format-List *
}

Invoke-CaptureBlock "INFO TAREAS PROGRAMADAS" {
    Get-ScheduledTaskInfo Enlace360_Agent,Enlace360_HealthCheck
}

Invoke-CaptureBlock "FORENSE TAREAS XML" {
    $taskFiles = @(
        (Join-Path $env:WINDIR "System32\Tasks\$TaskAgent"),
        (Join-Path $env:WINDIR "System32\Tasks\$TaskHealthCheck")
    )
    foreach ($taskFile in $taskFiles) {
        if (Test-Path -LiteralPath $taskFile -PathType Leaf) {
            Get-Item -LiteralPath $taskFile -Force | Select-Object FullName,Length,CreationTime,LastWriteTime,Attributes
            Get-Acl -LiteralPath $taskFile | Select-Object Path,Owner,AccessToString
        } else {
            [pscustomobject]@{ FullName = $taskFile; Exists = $false }
        }
    }
}

Invoke-CaptureBlock "FORENSE TASKSCHEDULER OPERATIONAL ENLACE360" {
    Get-WinEvent -LogName "Microsoft-Windows-TaskScheduler/Operational" -MaxEvents $EventScanMax -ErrorAction SilentlyContinue |
        Where-Object {
            $_.TimeCreated -ge $ForensicStart -and
            $_.Message -match "Enlace360|Agente_Enlace360|ProgramData\\Enlace360|KioskNetMonitor"
        } |
        Select-EventSummary |
        Select-Object -First $EventMax
}

Invoke-CaptureBlock "FORENSE SECURITY SCHEDULED TASKS" {
    Get-WinEvent -FilterHashtable @{ LogName = "Security"; Id = 4698,4699,4700,4701,4702; StartTime = $ForensicStart } -MaxEvents $EventScanMax -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match "Enlace360|Agente_Enlace360|ProgramData\\Enlace360|KioskNetMonitor" } |
        Select-EventSummary |
        Select-Object -First $EventMax
}

Invoke-CaptureBlock "FORENSE SECURITY PROCESS CREATION" {
    Get-WinEvent -FilterHashtable @{ LogName = "Security"; Id = 4688; StartTime = $ForensicStart } -MaxEvents $EventScanMax -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Message -match "schtasks|Register-ScheduledTask|Unregister-ScheduledTask|Stop-ScheduledTask|powershell|pwsh|Enlace360|KioskNetMonitor"
        } |
        Select-EventSummary |
        Select-Object -First $EventMax
}

Invoke-CaptureBlock "FORENSE POWERSHELL OPERATIONAL" {
    Get-WinEvent -LogName "Microsoft-Windows-PowerShell/Operational" -MaxEvents $EventScanMax -ErrorAction SilentlyContinue |
        Where-Object {
            $_.TimeCreated -ge $ForensicStart -and
            $_.Message -match "Enlace360|Agente_Enlace360|ProgramData\\Enlace360|KioskNetMonitor|schtasks|Register-ScheduledTask|Unregister-ScheduledTask|Stop-ScheduledTask"
        } |
        Select-EventSummary |
        Select-Object -First $EventMax
}

Invoke-CaptureBlock "FORENSE WINDOWS POWERSHELL" {
    Get-WinEvent -LogName "Windows PowerShell" -MaxEvents $EventScanMax -ErrorAction SilentlyContinue |
        Where-Object {
            $_.TimeCreated -ge $ForensicStart -and
            $_.Message -match "Enlace360|Agente_Enlace360|ProgramData\\Enlace360|KioskNetMonitor|schtasks|Register-ScheduledTask|Unregister-ScheduledTask|Stop-ScheduledTask"
        } |
        Select-EventSummary |
        Select-Object -First $EventMax
}

Invoke-CaptureBlock "FORENSE SERVICE CONTROL MANAGER ENLACE360" {
    Add-Line "--- Estado servicio actual ---"
    Get-Service -Name $ServiceName -ErrorAction SilentlyContinue | Select-Object Name,DisplayName,Status,StartType
    Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $ServiceName) -ErrorAction SilentlyContinue |
        Select-Object Name,State,StartMode,StartName,PathName,ProcessId
    Add-Line "--- System log Service Control Manager ---"
    Get-WinEvent -FilterHashtable @{ LogName = "System"; ProviderName = "Service Control Manager"; StartTime = $ForensicStart } -MaxEvents $EventScanMax -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match "Enlace360|Enlace360Agent|Agente_Enlace360|ProgramData\\Enlace360|winsw|PowerShell" } |
        Select-EventSummary |
        Select-Object -First $EventMax
}

Invoke-CaptureBlock "FORENSE EVENT LOG CLEARS" {
    foreach ($logName in @("Security", "System", "Application", "Microsoft-Windows-PowerShell/Operational", "Microsoft-Windows-TaskScheduler/Operational")) {
        Add-Line "--- $logName ---"
        Get-WinEvent -FilterHashtable @{ LogName = $logName; Id = 104,1102; StartTime = $ForensicStart } -MaxEvents $EventMax -ErrorAction SilentlyContinue |
            Select-EventSummary
    }
}

Invoke-CaptureBlock "FORENSE INSTALACION/DESINSTALACION" {
    Add-Line "--- Eventos MSI / instaladores ---"
    foreach ($logName in @("Application", "System")) {
        Add-Line "--- $logName ---"
        Get-WinEvent -LogName $logName -MaxEvents $EventScanMax -ErrorAction SilentlyContinue |
            Where-Object {
                $_.TimeCreated -ge $ForensicStart -and
                ($_.ProviderName -match "MsiInstaller|Service Control Manager|Windows Installer" -or $_.Message -match "install|instal|uninstall|desinstal|remove|elimin")
            } |
            Select-EventSummary |
            Select-Object -First $EventMax
    }
    Add-Line "--- Programas instalados relevantes ---"
    foreach ($uninstallPath in @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )) {
        Get-ItemProperty $uninstallPath -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match "TeamViewer|AnyDesk|RustDesk|ScreenConnect|ConnectWise|Splashtop|Atera|Ninja|VNC|ChromeRemoteDesktop|Enlace360|Cleaner|Limpia|Optimi|Revo|CCleaner" } |
            Select-Object DisplayName,DisplayVersion,Publisher,InstallDate,InstallLocation,UninstallString
    }
}

Invoke-CaptureBlock "FORENSE LOGONS REMOTOS" {
    Get-WinEvent -FilterHashtable @{ LogName = "Security"; Id = 4624,4625,4634,4647,4648,4672; StartTime = $ForensicStart } -MaxEvents $EventScanMax -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Message -match "Logon Type:\s+(2|7|10|11)|Tipo de inicio de sesion:\s+(2|7|10|11)|RemoteInteractive|Se le asignaron privilegios especiales|Special privileges|Explicit Credentials|Credenciales explicitas"
        } |
        Select-EventSummary |
        Select-Object -First $EventMax
}

Invoke-CaptureBlock "FORENSE TERMINAL SERVICES" {
    foreach ($logName in @(
        "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational",
        "Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational"
    )) {
        Add-Line "--- $logName ---"
        Get-WinEvent -LogName $logName -MaxEvents $EventScanMax -ErrorAction SilentlyContinue |
            Where-Object { $_.TimeCreated -ge $ForensicStart } |
            Select-EventSummary |
            Select-Object -First $EventMax
    }
}

Invoke-CaptureBlock "FORENSE HERRAMIENTAS REMOTAS" {
    $remotePattern = "TeamViewer|AnyDesk|RustDesk|ScreenConnect|ConnectWise|Splashtop|Atera|Ninja|Mesh|VNC|UltraViewer|ChromeRemoteDesktop|DWAgent|Tactical|RemotePC|LogMeIn"
    Add-Line "--- Servicios ---"
    Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $remotePattern -or $_.DisplayName -match $remotePattern } |
        Select-Object Name,DisplayName,Status,StartType
    Add-Line "--- Programas instalados ---"
    foreach ($uninstallPath in @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )) {
        Get-ItemProperty $uninstallPath -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match $remotePattern } |
            Select-Object DisplayName,DisplayVersion,Publisher,InstallDate,InstallLocation
    }
}

Invoke-CaptureBlock "FORENSE TEAMVIEWER LOGS" {
    $dest = Join-Path $OutDir "TeamViewerLogs"
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    $roots = @(
        "C:\Program Files\TeamViewer",
        "C:\Program Files (x86)\TeamViewer",
        "C:\ProgramData\TeamViewer",
        (Join-Path $env:APPDATA "TeamViewer"),
        (Join-Path $env:LOCALAPPDATA "TeamViewer")
    )
    foreach ($root in $roots) {
        Add-Line "--- $root ---"
        if (Test-Path -LiteralPath $root -PathType Container) {
            $files = Get-ChildItem -LiteralPath $root -Include "*.log","*.txt" -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -ge $ForensicStart -or $_.Name -match "Connections" } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 80
            $files | Select-Object FullName,Length,CreationTime,LastWriteTime
            foreach ($file in $files) {
                $safeName = ($file.FullName -replace "[:\\\/]", "_")
                Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $dest $safeName) -Force -ErrorAction SilentlyContinue
            }
        } else {
            Add-Line "(no existe)"
        }
    }
}

Invoke-CaptureBlock "FORENSE SCRIPTS SOSPECHOSOS LOCALES" {
    $roots = @(
        [Environment]::GetFolderPath("Desktop"),
        [Environment]::GetFolderPath("MyDocuments"),
        (Join-Path $env:USERPROFILE "Downloads"),
        "C:\Temp",
        "C:\ProgramData\Enlace360",
        "C:\ProgramData"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Select-Object -Unique
    foreach ($root in $roots) {
        Add-Line "--- $root ---"
        Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object {
                $_.LastWriteTime -ge $ForensicStart -and
                ($_.Extension -match "\.(ps1|bat|cmd|vbs|js|exe)$" -or $_.Name -match "Enlace360|KioskNetMonitor|Agente|Reparar|Validar|Limpia|Limpiador|SUPER|Cleaner|Clean|Reset|Arranque")
            } |
            Select-Object FullName,Length,CreationTime,LastWriteTime |
            Select-Object -First $EventMax
    }
}

Invoke-CaptureBlock "FORENSE DEFENDER ENLACE360" {
    Add-Line "--- Get-MpThreatDetection ---"
    if (Get-Command Get-MpThreatDetection -ErrorAction SilentlyContinue) {
        Get-MpThreatDetection -ErrorAction SilentlyContinue |
            Where-Object {
                ($_.Resources -join " ") -match "Enlace360|Agente_Enlace360|ProgramData\\Enlace360|KioskNetMonitor|PowerShell"
            } |
            Select-Object ThreatName,ActionSuccess,InitialDetectionTime,LastThreatStatusChangeTime,Resources
    } else {
        Add-Line "Get-MpThreatDetection no disponible."
    }
    Add-Line "--- Microsoft-Windows-Windows Defender/Operational ---"
    Get-WinEvent -LogName "Microsoft-Windows-Windows Defender/Operational" -MaxEvents $EventScanMax -ErrorAction SilentlyContinue |
        Where-Object {
            $_.TimeCreated -ge $ForensicStart -and
            $_.Message -match "Enlace360|Agente_Enlace360|ProgramData\\Enlace360|KioskNetMonitor|PowerShell|ScheduledTask|Task Scheduler"
        } |
        Select-EventSummary |
        Select-Object -First $EventMax
}

Invoke-CaptureBlock "FORENSE DEFENDER COMPLETO" {
    Add-Line "--- Get-MpThreatDetection completo ---"
    if (Get-Command Get-MpThreatDetection -ErrorAction SilentlyContinue) {
        Get-MpThreatDetection -ErrorAction SilentlyContinue |
            Sort-Object LastThreatStatusChangeTime -Descending |
            Select-Object -First $EventMax -Property ThreatName,ActionSuccess,InitialDetectionTime,LastThreatStatusChangeTime,Resources
    } else {
        Add-Line "Get-MpThreatDetection no disponible."
    }
    Add-Line "--- Defender Operational completo reciente ---"
    Get-WinEvent -LogName "Microsoft-Windows-Windows Defender/Operational" -MaxEvents $EventScanMax -ErrorAction SilentlyContinue |
        Where-Object { $_.TimeCreated -ge $ForensicStart } |
        Select-EventSummary |
        Select-Object -First $EventMax
}

Invoke-CaptureBlock "FORENSE AUDIT POLICY" {
    foreach ($subcategory in @("Other Object Access Events", "Process Creation", "Logon", "Special Logon")) {
        Add-Line "--- $subcategory ---"
        $auditArgs = @("/get", "/subcategory:$subcategory")
        & auditpol.exe @auditArgs 2>&1
    }
}

Invoke-CaptureBlock "PROCESOS ENLACE360" {
    Get-CimInstance Win32_Process |
        Where-Object { $_.CommandLine -match "Enlace360|Agente_Enlace360" } |
        Select-Object ProcessId,Name,CommandLine
}

Invoke-CaptureBlock "AGENTE LOG TAIL" {
    Get-Content (Join-Path $InstallDir "agente.log") -Tail $AgentLogTail -ErrorAction SilentlyContinue
}

Invoke-CaptureBlock "HEALTHCHECK LOG TAIL" {
    Get-Content (Join-Path $InstallDir "healthcheck.log") -Tail $HealthLogTail -ErrorAction SilentlyContinue
}

Invoke-CaptureBlock "C2 LOG TAIL" {
    Get-Content (Join-Path $InstallDir "c2.log") -Tail $C2LogTail -ErrorAction SilentlyContinue
}

Invoke-CaptureBlock "ESTADO LOCAL RED" {
    Get-Content C:\ProgramData\Enlace360\Agent\network_state.json -ErrorAction SilentlyContinue
}

Invoke-CaptureBlock "ESTADO LAZARO" {
    Get-Content C:\ProgramData\Enlace360\Agent\lazaro_count.txt -ErrorAction SilentlyContinue
}

# Contrato diagnostico: powercfg.exe /lastwake
# Contrato diagnostico: powercfg.exe /a
# Contrato diagnostico: powercfg.exe /query SCHEME_CURRENT SUB_SLEEP
Invoke-CaptureCommand "POWERCFG LASTWAKE" "powercfg.exe" @("/lastwake")
Invoke-CaptureCommand "POWERCFG AVAILABLE SLEEP STATES" "powercfg.exe" @("/a")
Invoke-CaptureCommand "POWERCFG SUB_SLEEP" "powercfg.exe" @("/query", "SCHEME_CURRENT", "SUB_SLEEP")

Invoke-CaptureBlock "EVENTOS SISTEMA ENERGIA/APAGADO" {
    Get-WinEvent -FilterHashtable @{LogName='System'; Id=41,42,107,109,6005,6006,6008,1} -MaxEvents $EventMax |
        Select-Object TimeCreated,Id,ProviderName,Message
}

Invoke-CaptureBlock "ADAPTADORES FISICOS" {
    Get-NetAdapter -Physical | Select-Object Name,Status,LinkSpeed,MacAddress,InterfaceDescription
}

Invoke-CaptureBlock "CONFIGURACION IP" {
    Get-NetIPConfiguration
}

Invoke-CaptureBlock "PING 8.8.8.8" {
    Test-Connection 8.8.8.8 -Count 4
}

Invoke-CaptureBlock "DNS GOOGLE" {
    Resolve-DnsName google.com
}

Invoke-CaptureBlock "SUPABASE KIOSK ROW" {
    $agentPath = Join-Path $InstallDir "Agente_Enlace360_Service.ps1"
    $configPath = Join-Path $InstallDir "config.json"
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw "No existe $configPath" }
    $supabase = Read-SupabaseCredentials -AgentPath $agentPath
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $kioskName = [string]$config.KioskName
    $encoded = [uri]::EscapeDataString($kioskName)
    Add-Line ("Credenciales leidas desde: {0}" -f $supabase.Source)
    $row = Invoke-SupabaseJson -Uri "$($supabase.Url)/rest/v1/kiosks?kiosk_id=eq.$encoded&select=kiosk_id,status,last_heartbeat,uptime,ip_address,mac_address,latency_ms,updated_at,integrity_status,integrity_alert,integrity_checked_at,integrity_details" -Headers $supabase.Headers
    $row | ConvertTo-Json -Depth 6
}

Invoke-CaptureBlock "SUPABASE REMOTE COMMANDS PENDING" {
    $agentPath = Join-Path $InstallDir "Agente_Enlace360_Service.ps1"
    $configPath = Join-Path $InstallDir "config.json"
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw "No existe $configPath" }
    $adminSecret = Get-C2AdminSecret
    if ([string]::IsNullOrWhiteSpace($adminSecret)) {
        Add-Line "Omitido: define ENLACE360_C2_ADMIN_SECRET para consultar C2 seguro."
        return
    }
    $supabase = Read-SupabaseCredentials -AgentPath $agentPath
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    Add-Line ("Credenciales leidas desde: {0}" -f $supabase.Source)
    $commands = Invoke-SupabaseJson -Uri "$($supabase.Url)/rest/v1/rpc/enlace360_list_remote_commands" -Method "POST" -Headers $supabase.Headers -Body @{
        p_admin_secret = $adminSecret
        p_kiosk_id = [string]$config.KioskName
        p_limit = 100
    }
    $pending = @($commands | Where-Object { $_.status -eq "pending" })
    $pending | ConvertTo-Json -Depth 6
}

Invoke-CaptureBlock "SUPABASE REMOTE COMMANDS RECIENTES" {
    $agentPath = Join-Path $InstallDir "Agente_Enlace360_Service.ps1"
    $configPath = Join-Path $InstallDir "config.json"
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw "No existe $configPath" }
    $adminSecret = Get-C2AdminSecret
    if ([string]::IsNullOrWhiteSpace($adminSecret)) {
        Add-Line "Omitido: define ENLACE360_C2_ADMIN_SECRET para consultar C2 seguro."
        return
    }
    $supabase = Read-SupabaseCredentials -AgentPath $agentPath
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    Add-Line ("Credenciales leidas desde: {0}" -f $supabase.Source)
    $recent = Invoke-SupabaseJson -Uri "$($supabase.Url)/rest/v1/rpc/enlace360_list_remote_commands" -Method "POST" -Headers $supabase.Headers -Body @{
        p_admin_secret = $adminSecret
        p_kiosk_id = [string]$config.KioskName
        p_limit = 50
    }
    $recent | ConvertTo-Json -Depth 6
}

if ($RunVerifier) {
    Invoke-CaptureBlock "VERIFICADOR FINAL" {
        $verifier = Join-Path $InstallDir "Verificar_Enlace360_SYSTEM.ps1"
        if (-not (Test-Path -LiteralPath $verifier -PathType Leaf)) { throw "No existe $verifier" }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifier -InstallDir $InstallDir -ObserveSeconds $VerifierObserveSeconds
    }
}

foreach ($path in @(
    "C:\Enlace360_SYSTEM_installer.log",
    "C:\Enlace360_SYSTEM_verifier.log",
    (Join-Path $InstallDir "agente.log"),
    (Join-Path $InstallDir "healthcheck.log"),
    (Join-Path $InstallDir "c2.log"),
    (Join-Path $InstallDir "config.json"),
    (Join-Path $InstallDir "integrity_state.json"),
    (Join-Path $InstallDir "network_state.json"),
    (Join-Path $InstallDir "lazaro_count.txt"),
    (Join-Path $InstallDir "install_manifest.json"),
    (Join-Path $InstallDir "agent_payload.cache"),
    (Join-Path $InstallDir "healthcheck_payload.cache"),
    (Join-Path $InstallDir "Enlace360Agent.xml")
)) {
    Copy-EvidenceFile -Path $path
}

Copy-EvidenceDirectory -Path (Join-Path $InstallDir "service-logs")

Add-Section "ARCHIVOS DE EVIDENCIA COPIADOS"
Get-ChildItem -LiteralPath $OutDir -Force | Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize | Out-String -Width 240 | ForEach-Object {
    $_.TrimEnd() -split "`r?`n" | ForEach-Object { Add-Line $_ }
}

try {
    if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force -ErrorAction SilentlyContinue }
    Compress-Archive -Path (Join-Path $OutDir "*") -DestinationPath $ZipPath -Force
    Add-Line ""
    Add-Line ("ZIP={0}" -f $ZipPath)
} catch {
    Add-Line ("[WARN] No se pudo generar ZIP: {0}" -f $_.Exception.Message)
}

Add-Line ""
Add-Line ("Reporte={0}" -f $ReportPath)
Add-Line "Diagnostico terminado."
exit 0
