param(
    [string]$InstallDir = "C:\ProgramData\Enlace360\Agent",
    [int]$ObserveSeconds = 150,
    [switch]$TestHealthCheck
)

$ErrorActionPreference = "Stop"
$VerifierVersion = "SYSTEM-2026-05-09.2"
$PreferredLogFile = "C:\Enlace360_SYSTEM_verifier.log"
$LogFile = $PreferredLogFile
$TaskAgent = "Enlace360_Agent"
$TaskHealthCheck = "Enlace360_HealthCheck"
$ServiceName = "Enlace360Agent"
$Checks = New-Object System.Collections.Generic.List[object]

try {
    "" | Out-File -FilePath $LogFile -Force -Encoding UTF8 -ErrorAction Stop
    Remove-Item -LiteralPath $LogFile -Force -ErrorAction SilentlyContinue
} catch {
    $LogFile = Join-Path $env:TEMP "Enlace360_SYSTEM_verifier.log"
    Remove-Item -LiteralPath $LogFile -Force -ErrorAction SilentlyContinue
}

function Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    $line | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

function Add-Check {
    param([string]$Name, [bool]$Passed, [string]$Details = "")
    $status = if ($Passed) { "PASS" } else { "FAIL" }
    $Checks.Add([pscustomobject]@{ Status = $status; Name = $Name; Details = $Details }) | Out-Null
    $color = if ($Passed) { "Green" } else { "Red" }
    Write-Host ("[{0}] {1} {2}" -f $status, $Name, $Details) -ForegroundColor $color
    ("[{0}] {1} {2}" -f $status, $Name, $Details) | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

function Invoke-Check {
    param([string]$Name, [scriptblock]$Body)
    try {
        $details = & $Body
        if ($null -eq $details) { $details = "" }
        Add-Check -Name $Name -Passed $true -Details ([string]$details)
        return $true
    } catch {
        Add-Check -Name $Name -Passed $false -Details $_.Exception.Message
        return $false
    }
}

function Finish-Verification {
    Log "===== RESUMEN ====="
    $Checks | Format-Table Status,Name,Details -AutoSize | Out-String | Out-File -FilePath $LogFile -Append -Encoding UTF8
    $failed = @($Checks | Where-Object { $_.Status -ne "PASS" })
    if ($failed.Count -gt 0) {
        Write-Host ""
        Write-Host "[FAIL] Verificacion SYSTEM con $($failed.Count) falla(s). Log: $LogFile" -ForegroundColor Red
        exit 1
    }
    Write-Host ""
    Write-Host "PASS VERIFICACION SYSTEM ENLACE360. Log: $LogFile" -ForegroundColor Green
    exit 0
}

function Wait-Until {
    param(
        [string]$Label,
        [scriptblock]$Condition,
        [int]$TimeoutSeconds = 120,
        [int]$IntervalSeconds = 3
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

function Read-AgentSupabase {
    param([string]$AgentPath)
    $source = Get-Content -LiteralPath $AgentPath -Raw
    $url = [regex]::Match($source, '\$SupabaseUrl\s*=\s*"([^"]+)"').Groups[1].Value
    $key = [regex]::Match($source, '\$SupabaseAnonKey\s*=\s*"([^"]+)"').Groups[1].Value
    if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($key)) {
        throw "No pude leer credenciales Supabase desde $AgentPath"
    }
    return @{ Url = $url; Key = $key; Headers = @{ apikey = $key; Authorization = "Bearer $key" } }
}

function Get-C2AdminSecret {
    if ([string]::IsNullOrWhiteSpace($env:ENLACE360_C2_ADMIN_SECRET)) {
        return ""
    }
    return [string]$env:ENLACE360_C2_ADMIN_SECRET
}

function Restore-AgentFromCache {
    param([string]$AgentPath, [string]$AgentCachePath)
    if (Test-Path -LiteralPath $AgentPath -PathType Leaf) { return "agente presente" }
    if (-not (Test-Path -LiteralPath $AgentCachePath -PathType Leaf)) {
        throw "Falta agente y cache local: $AgentPath / $AgentCachePath"
    }
    $payload = [System.IO.File]::ReadAllText($AgentCachePath).Trim()
    $bytes = [Convert]::FromBase64String($payload)
    [System.IO.File]::WriteAllBytes($AgentPath, $bytes)
    return "agente restaurado desde agent_payload.cache"
}

function Restore-HealthCheckFromCache {
    param([string]$HealthCheckPath, [string]$HealthCheckCachePath)
    if (Test-Path -LiteralPath $HealthCheckPath -PathType Leaf) { return "healthcheck presente" }
    if (-not (Test-Path -LiteralPath $HealthCheckCachePath -PathType Leaf)) {
        throw "Falta healthcheck y cache local: $HealthCheckPath / $HealthCheckCachePath"
    }
    $payload = [System.IO.File]::ReadAllText($HealthCheckCachePath).Trim()
    $bytes = [Convert]::FromBase64String($payload)
    [System.IO.File]::WriteAllBytes($HealthCheckPath, $bytes)
    return "healthcheck restaurado desde healthcheck_payload.cache"
}

function Invoke-SupabaseJson {
    param(
        [string]$Uri,
        [string]$Method,
        [hashtable]$Headers,
        [object]$Body = $null,
        [hashtable]$ExtraHeaders = @{}
    )
    $requestHeaders = $Headers.Clone()
    foreach ($key in $ExtraHeaders.Keys) { $requestHeaders[$key] = $ExtraHeaders[$key] }
    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 6
        return Invoke-RestMethod -Uri $Uri -Method $Method -Headers $requestHeaders -Body $json -ContentType "application/json; charset=utf-8" -TimeoutSec 20 -ErrorAction Stop
    }
    return Invoke-RestMethod -Uri $Uri -Method $Method -Headers $requestHeaders -TimeoutSec 20 -ErrorAction Stop
}

function Get-KioskRow {
    param($Supabase, [string]$KioskName)
    $encoded = [uri]::EscapeDataString($KioskName)
    $rows = Invoke-SupabaseJson -Uri "$($Supabase.Url)/rest/v1/kiosks?kiosk_id=eq.$encoded&select=kiosk_id,status,last_heartbeat,uptime,ip_address,mac_address,latency_ms,integrity_status,integrity_alert,integrity_checked_at,integrity_details" -Method "GET" -Headers $Supabase.Headers
    return @($rows) | Select-Object -First 1
}

function Test-C2Roundtrip {
    param($Supabase, [string]$KioskName)
    $adminSecret = Get-C2AdminSecret
    if ([string]::IsNullOrWhiteSpace($adminSecret)) {
        return "C2 roundtrip omitido: define ENLACE360_C2_ADMIN_SECRET para probar RPC seguro"
    }

    $nonce = "ENLACE360_SYSTEM_{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 12))
    $created = Invoke-SupabaseJson -Uri "$($Supabase.Url)/rest/v1/rpc/enlace360_enqueue_remote_command" -Method "POST" -Headers $Supabase.Headers -Body @{
        p_admin_secret = $adminSecret
        p_kiosk_id = $KioskName
        p_command_string = "Write-Output '$nonce'"
        p_requested_by = "verificador"
    }
    $id = [string]$created
    if (-not $id) { throw "Supabase no retorno id de remote_commands" }

    Start-ScheduledTask -TaskName $TaskHealthCheck -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    Wait-Until -Label "C2 roundtrip $id" -TimeoutSeconds 150 -IntervalSeconds 5 -Condition {
        $commands = Invoke-SupabaseJson -Uri "$($Supabase.Url)/rest/v1/rpc/enlace360_list_remote_commands" -Method "POST" -Headers $Supabase.Headers -Body @{
            p_admin_secret = $adminSecret
            p_kiosk_id = $KioskName
            p_limit = 50
        }
        $cmd = @($commands) | Where-Object { [string]$_.id -eq [string]$id } | Select-Object -First 1
        if (-not $cmd -or $cmd.status -eq "pending") { return $false }
        if ($cmd.status -eq "in_progress") { return $false }
        if ($cmd.status -ne "executed") { throw "C2 termino $($cmd.status): $($cmd.output_log)" }
        if ($cmd.output_log -notlike "*$nonce*") { throw "C2 sin nonce. Output=$($cmd.output_log)" }
        return $true
    }
    return "id=$id"
}

function Wait-FreshHeartbeat {
    param(
        $Supabase,
        [string]$KioskName,
        [int]$TimeoutSeconds = 150
    )
    $script:freshHeartbeatRow = $null
    Wait-Until -Label "heartbeat Supabase fresco" -TimeoutSeconds $TimeoutSeconds -IntervalSeconds 5 -Condition {
        $row = Get-KioskRow -Supabase $Supabase -KioskName $KioskName
        if (-not $row -or -not $row.last_heartbeat) {
            Log "Heartbeat observado: sin fila/last_heartbeat"
            return $false
        }
        $hb = ([datetime]$row.last_heartbeat).ToUniversalTime()
        $age = (Get-Date).ToUniversalTime() - $hb
        Log "Heartbeat observado=$($row.last_heartbeat); uptime=$($row.uptime); age=$([int]$age.TotalSeconds)s"
        if ($age.TotalMinutes -le 5) {
            $script:freshHeartbeatRow = $row
            return $true
        }
        return $false
    }
    return "last_heartbeat=$($script:freshHeartbeatRow.last_heartbeat); uptime=$($script:freshHeartbeatRow.uptime)"
}

function Wait-HeartbeatAdvance {
    param($Supabase, [string]$KioskName, [int]$Seconds)
    $first = Get-KioskRow -Supabase $Supabase -KioskName $KioskName
    if (-not $first -or -not $first.last_heartbeat) { throw "No hay fila/heartbeat inicial en Supabase" }
    $firstHeartbeat = ([datetime]$first.last_heartbeat).ToUniversalTime()
    $firstUptime = [string]$first.uptime
    Log "Heartbeat inicial=$($first.last_heartbeat); uptime=$firstUptime"
    if ($Seconds -le 0) { return "observacion omitida; heartbeat=$($first.last_heartbeat); uptime=$firstUptime" }

    $script:advancedRow = $null
    Wait-Until -Label "heartbeat/dashboard avanza" -TimeoutSeconds $Seconds -IntervalSeconds 10 -Condition {
        $script:advancedRow = Get-KioskRow -Supabase $Supabase -KioskName $KioskName
        if (-not $script:advancedRow -or -not $script:advancedRow.last_heartbeat) { return $false }
        $hb = ([datetime]$script:advancedRow.last_heartbeat).ToUniversalTime()
        $uptime = [string]$script:advancedRow.uptime
        Log "Heartbeat observado=$($script:advancedRow.last_heartbeat); uptime=$uptime"
        return ($hb -gt $firstHeartbeat -or $uptime -ne $firstUptime)
    }
    return "antes=$($first.last_heartbeat) uptime=$firstUptime; despues=$($script:advancedRow.last_heartbeat) uptime=$($script:advancedRow.uptime)"
}

function Write-Tail {
    param([string]$Title, [string]$Path, [int]$Tail = 80)
    Log "===== $Title ====="
    if (Test-Path -LiteralPath $Path) {
        Get-Content -LiteralPath $Path -Tail $Tail -ErrorAction SilentlyContinue | ForEach-Object { Log $_ }
    } else {
        Log "No existe $Path"
    }
}

Log "===== VERIFICACION SYSTEM ENLACE360 ====="
Log "VerifierVersion=$VerifierVersion"
Log "InstallDir=$InstallDir"
Log "ObserveSeconds=$ObserveSeconds"
Log "TestHealthCheck=$TestHealthCheck"

$AgentPath = Join-Path $InstallDir "Agente_Enlace360_Service.ps1"
$AgentCachePath = Join-Path $InstallDir "agent_payload.cache"
$HealthCheckPath = Join-Path $InstallDir "Enlace360_HealthCheck.ps1"
$HealthCheckCachePath = Join-Path $InstallDir "healthcheck_payload.cache"
$ConfigPath = Join-Path $InstallDir "config.json"
$ServiceExePath = Join-Path $InstallDir "Enlace360Agent.exe"
$ServiceXmlPath = Join-Path $InstallDir "Enlace360Agent.xml"

if (-not (Invoke-Check "Archivos instalados" {
    $restoreResult = Restore-AgentFromCache -AgentPath $AgentPath -AgentCachePath $AgentCachePath
    $healthRestoreResult = Restore-HealthCheckFromCache -HealthCheckPath $HealthCheckPath -HealthCheckCachePath $HealthCheckCachePath
    foreach ($path in @($AgentPath, $AgentCachePath, $HealthCheckPath, $HealthCheckCachePath, $ConfigPath, $ServiceExePath, $ServiceXmlPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Falta $path" }
    }
    $datFiles = @(Get-ChildItem -LiteralPath $InstallDir -Filter "*.dat" -File -ErrorAction SilentlyContinue)
    if ($datFiles.Count -gt 0) { throw "No deben existir payloads .dat: $($datFiles.Name -join ', ')" }
    "OK; $restoreResult; $healthRestoreResult"
})) { Finish-Verification }

if (-not (Invoke-Check "Config local" {
    $script:Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace([string]$script:Config.KioskName)) { throw "KioskName vacio" }
    "kiosk=$($script:Config.KioskName); location=$($script:Config.Location); client=$($script:Config.ClientName)"
})) { Finish-Verification }

if (-not (Invoke-Check "Credenciales Supabase" {
    $script:Supabase = Read-AgentSupabase -AgentPath $AgentPath
    $script:Supabase.Url
})) { Finish-Verification }

if (-not (Invoke-Check "Tareas SYSTEM" {
    $details = @()
    foreach ($taskName in @($TaskAgent, $TaskHealthCheck)) {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if (-not $task) { throw "No existe tarea $taskName" }
        if ($task.Principal.UserId -ne "SYSTEM") { throw "$taskName no corre como SYSTEM: $($task.Principal.UserId)" }
        $info = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
        $details += "$taskName=$($task.State)/Last=$($info.LastTaskResult)"
    }
    $details -join "; "
})) { Finish-Verification }

if (-not (Invoke-Check "Servicio Windows Enlace360Agent" {
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) { throw "No existe servicio $ServiceName" }
    $svcInfo = Get-CimInstance Win32_Service -Filter ("Name='$ServiceName'") -ErrorAction SilentlyContinue
    if ($svcInfo.StartMode -ne "Auto") { throw "$ServiceName no esta en Automatic: $($svcInfo.StartMode)" }
    if ($svc.Status -ne "Running") {
        Start-Service -Name $ServiceName -ErrorAction Stop
        Wait-Until -Label "servicio $ServiceName running" -TimeoutSeconds 60 -Condition { (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue).Status -eq "Running" }
        $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    }
    "$ServiceName=$($svc.Status); start_mode=$($svcInfo.StartMode)"
})) { Finish-Verification }

Invoke-Check "Proceso agente vivo" {
    $proc = @(Get-AgentProcess)
    if ($proc.Count -lt 1) {
        Start-ScheduledTask -TaskName $TaskAgent -ErrorAction Stop
        Wait-Until -Label "proceso agente vivo" -TimeoutSeconds 80 -Condition { @(Get-AgentProcess).Count -gt 0 }
        $proc = @(Get-AgentProcess)
    }
    "pid=$($proc[0].ProcessId)"
} | Out-Null

Invoke-Check "Heartbeat Supabase fresco" {
    Wait-FreshHeartbeat -Supabase $script:Supabase -KioskName ([string]$script:Config.KioskName)
} | Out-Null

Invoke-Check "Integridad reportada dashboard" {
    $row = Get-KioskRow -Supabase $script:Supabase -KioskName ([string]$script:Config.KioskName)
    if (-not $row) { throw "No hay fila kiosk en Supabase" }
    if ([string]::IsNullOrWhiteSpace([string]$row.integrity_status)) { throw "Falta integrity_status. Ejecuta supabase_schema.sql actualizado." }
    if ($row.integrity_status -eq "critical") { throw "integrity_status=critical; $($row.integrity_alert)" }
    "integrity_status=$($row.integrity_status); alert=$($row.integrity_alert)"
} | Out-Null

Invoke-Check "Contador dashboard/heartbeat avanza" {
    Wait-HeartbeatAdvance -Supabase $script:Supabase -KioskName ([string]$script:Config.KioskName) -Seconds $ObserveSeconds
} | Out-Null

Invoke-Check "C2 roundtrip real" {
    Test-C2Roundtrip -Supabase $script:Supabase -KioskName ([string]$script:Config.KioskName)
} | Out-Null

if ($TestHealthCheck) {
    Invoke-Check "HealthCheck recupera proceso muerto" {
        @(Get-AgentProcess) | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 4
        Start-ScheduledTask -TaskName $TaskHealthCheck -ErrorAction Stop
        Wait-Until -Label "healthcheck relanza agente" -TimeoutSeconds 90 -Condition { @(Get-AgentProcess).Count -gt 0 }
        "OK"
    } | Out-Null

    Invoke-Check "HealthCheck restaura archivo agente" {
        $backup = "$AgentPath.selftest.bak"
        try {
            @(Get-AgentProcess) | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
            [System.IO.File]::Copy($AgentPath, $backup, $true)
            Remove-Item -LiteralPath $AgentPath -Force
            Start-ScheduledTask -TaskName $TaskHealthCheck -ErrorAction Stop
            Wait-Until -Label "healthcheck restaura archivo agente" -TimeoutSeconds 90 -Condition {
                (Test-Path -LiteralPath $AgentPath -PathType Leaf) -and @(Get-AgentProcess).Count -gt 0
            }
            "OK"
        } finally {
            if ((-not (Test-Path -LiteralPath $AgentPath -PathType Leaf)) -and (Test-Path -LiteralPath $backup -PathType Leaf)) {
                [System.IO.File]::Copy($backup, $AgentPath, $true)
            }
            Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
        }
    } | Out-Null

    Invoke-Check "HealthCheck recrea tarea principal" {
        Stop-ScheduledTask -TaskName $TaskAgent -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskAgent -Confirm:$false -ErrorAction SilentlyContinue
        Start-ScheduledTask -TaskName $TaskHealthCheck -ErrorAction Stop
        Wait-Until -Label "healthcheck recrea tarea principal" -TimeoutSeconds 90 -Condition {
            $task = Get-ScheduledTask -TaskName $TaskAgent -ErrorAction SilentlyContinue
            return ($task -and $task.Principal.UserId -eq "SYSTEM")
        }
        "OK"
    } | Out-Null
}

Invoke-Check "Pending remote_commands vacio" {
    $adminSecret = Get-C2AdminSecret
    if ([string]::IsNullOrWhiteSpace($adminSecret)) {
        return "Pending remote_commands omitido: define ENLACE360_C2_ADMIN_SECRET para consultar RPC seguro"
    }
    $pending = Invoke-SupabaseJson -Uri "$($script:Supabase.Url)/rest/v1/rpc/enlace360_list_remote_commands" -Method "POST" -Headers $script:Supabase.Headers -Body @{
        p_admin_secret = $adminSecret
        p_kiosk_id = [string]$script:Config.KioskName
        p_limit = 100
    }
    $items = @($pending)
    $stillPending = @($items | Where-Object { $_.status -eq "pending" })
    if ($stillPending.Count -gt 0) { throw "Pending remote_commands=$($stillPending.id -join ',')" }
    "Pending remote_commands=[]"
} | Out-Null

Write-Tail -Title "AGENTE LOG" -Path (Join-Path $InstallDir "agente.log") -Tail 60
Write-Tail -Title "HEALTHCHECK LOG" -Path (Join-Path $InstallDir "healthcheck.log") -Tail 40

Finish-Verification
