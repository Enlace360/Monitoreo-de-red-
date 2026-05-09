<#
.SYNOPSIS
    Kiosk Network Monitor - Agente Inteligente (Enterprise Daemon Edition)
.DESCRIPTION
    Version blindada para produccion (NT AUTHORITY\SYSTEM).
    - Logs rotativos locales (agente.log)
    - Prevencion de bucles infinitos en comandos C2 (Timeout 60s)
    - Tolerancia a corrupcion de estado por cortes electricos
    - Auto-reinicio tras actualizacion remota
#>

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ============================================================================
# CONFIGURACION MAESTRA
# ============================================================================
$SupabaseUrl = "https://zhvykvpixpkjegfxgwer.supabase.co"
$SupabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpodnlrdnBpeHBramVnZnhnd2VyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc0ODI3NTksImV4cCI6MjA5MzA1ODc1OX0.kE0BA4IyldzvX4XfhF3bHAARTRDkAlqSgAlM6Am5YdI"
$AgentVersion = "v3.8"

$CheckIntervalSecs = 30
$HttpTimeoutSecs = 10
$ScriptPath = if ($env:ENLACE360_AGENT_SOURCE) {
    $env:ENLACE360_AGENT_SOURCE
} elseif ($PSCommandPath) {
    $PSCommandPath
} else {
    $MyInvocation.MyCommand.Path
}
$LogDir = if (-not [string]::IsNullOrWhiteSpace($ScriptPath)) {
    Split-Path -Parent $ScriptPath
} else {
    "C:\ProgramData\KioskNetMonitor"
}

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

$ConfigFile = Join-Path $LogDir "config.json"
$StateFile = Join-Path $LogDir "network_state.json"
$HeartbeatFile = Join-Path $LogDir "last_heartbeat.txt"
$LogFile = Join-Path $LogDir "agente.log"
$IntegrityFile = Join-Path $LogDir "integrity_state.json"
$ServiceName = "Enlace360Agent"
$TaskAgent = "Enlace360_Agent"
$TaskHealthCheck = "Enlace360_HealthCheck"

$Headers = @{
    "apikey" = $SupabaseAnonKey
    "Authorization" = "Bearer $SupabaseAnonKey"
}

# ============================================================================
# SISTEMA DE LOGS LOCALES
# ============================================================================
Function Write-Log {
    param([string]$Message)
    $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logLine = "[$stamp] $Message"

    if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt 2MB)) {
        Move-Item $LogFile "$LogFile.old" -Force
    }

    $logLine | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

$createdNewMutex = $false
try {
    $AgentMutex = New-Object System.Threading.Mutex($true, "Global\Enlace360AgentDaemon", [ref]$createdNewMutex)
    if (-not $createdNewMutex) {
        Write-Log "[INFO] Ya existe una instancia activa del agente. Saliendo para evitar proceso duplicado."
        exit 0
    }
} catch {
    Write-Log "[WARNING] No se pudo crear mutex de instancia unica: $($_.Exception.Message)"
}

Function Invoke-EnlaceRestJson {
    param(
        [string]$Uri,
        [string]$Method,
        [hashtable]$Headers,
        [string]$JsonBody = $null
    )

    $job = Start-Job -ScriptBlock {
        param($Uri, $Method, $Headers, $JsonBody, $HttpTimeoutSecs)

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        $request = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($Uri)
        $request.Method = $Method
        $request.Timeout = $HttpTimeoutSecs * 1000
        $request.ReadWriteTimeout = $HttpTimeoutSecs * 1000
        $request.Accept = "application/json"

        foreach ($key in $Headers.Keys) {
            if ($key -ieq "Content-Type") {
                $request.ContentType = [string]$Headers[$key]
            } else {
                $request.Headers[$key] = [string]$Headers[$key]
            }
        }

        if (-not [string]::IsNullOrEmpty($JsonBody)) {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($JsonBody)
            $request.ContentType = "application/json; charset=utf-8"
            $request.ContentLength = $bytes.Length
            $stream = $request.GetRequestStream()
            try {
                $stream.Write($bytes, 0, $bytes.Length)
            } finally {
                $stream.Dispose()
            }
        }

        try {
            $response = [System.Net.HttpWebResponse]$request.GetResponse()
            try {
                $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
                try {
                    $reader.ReadToEnd()
                } finally {
                    $reader.Dispose()
                }
            } finally {
                $response.Dispose()
            }
        } catch [System.Net.WebException] {
            $message = $_.Exception.Message
            if ($_.Exception.Response) {
                $errorResponse = [System.Net.HttpWebResponse]$_.Exception.Response
                try {
                    $errorReader = New-Object System.IO.StreamReader($errorResponse.GetResponseStream())
                    try {
                        $errorBody = $errorReader.ReadToEnd()
                    } finally {
                        $errorReader.Dispose()
                    }
                    $message = "HTTP $([int]$errorResponse.StatusCode) $($errorResponse.StatusDescription): $errorBody"
                } finally {
                    $errorResponse.Dispose()
                }
            }
            throw $message
        }
    } -ArgumentList $Uri, $Method, $Headers, $JsonBody, $HttpTimeoutSecs

    $completed = Wait-Job -Job $job -Timeout ($HttpTimeoutSecs + 3)
    if (-not $completed) {
        Stop-Job -Job $job -Force
        Remove-Job -Job $job -Force
        throw "Timeout HTTP: Supabase no respondio en $($HttpTimeoutSecs + 3) segundos."
    }

    try {
        $text = (Receive-Job -Job $job -ErrorAction Stop) -join [Environment]::NewLine
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        return $text | ConvertFrom-Json
    } finally {
        Remove-Job -Job $job -Force
    }
}

Function Send-RestRequest {
    param([string]$Uri, [string]$Method, [hashtable]$Headers, [string]$JsonBody)
    Invoke-EnlaceRestJson -Uri $Uri -Method $Method -Headers $Headers -JsonBody $JsonBody
}

Function New-AgentSecret {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
        return [Convert]::ToBase64String($bytes)
    } finally {
        $rng.Dispose()
    }
}

Function Get-Sha256Hex {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

Function Invoke-WithTimeout {
    param(
        [scriptblock]$ScriptBlock,
        [int]$TimeoutSeconds = 8,
        [object[]]$ArgumentList = @()
    )

    $job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
    if (-not $completed) {
        Stop-Job -Job $job -Force
        Remove-Job -Job $job -Force
        throw "Timeout despues de $TimeoutSeconds segundos."
    }

    try {
        Receive-Job -Job $job -ErrorAction Stop
    } finally {
        Remove-Job -Job $job -Force
    }
}

# ============================================================================
# CARGA DE CONFIGURACION (MODO SILENCIOSO)
# ============================================================================
if (Test-Path $ConfigFile) {
    try {
        $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        $ClientName = $config.ClientName
        $Location = $config.Location
        $KioskName = $config.KioskName
        $AgentSecret = [string]$config.AgentSecret
    } catch {
        Write-Log "[ERROR] Archivo config.json corrupto. Usando valores por defecto."
        $ClientName = "Desconocido"
        $Location = "Sin Ubicacion"
        $KioskName = "KIOSCO-" + $env:COMPUTERNAME
        $AgentSecret = ""
    }
} else {
    $ClientName = "Desconocido"
    $Location = "Sin Ubicacion"
    $KioskName = "KIOSCO-" + $env:COMPUTERNAME
    $AgentSecret = ""
}

if ([string]::IsNullOrWhiteSpace($AgentSecret)) {
    $AgentSecret = New-AgentSecret
    try {
        [ordered]@{
            ClientName = $ClientName
            Location = $Location
            KioskName = $KioskName
            AgentSecret = $AgentSecret
        } | ConvertTo-Json | Set-Content -LiteralPath $ConfigFile -Encoding UTF8 -Force
        Write-Log "[SECURITY] AgentSecret local creado en config.json."
    } catch {
        Write-Log "[ERROR] No se pudo persistir AgentSecret en config.json: $($_.Exception.Message)"
    }
}

$Headers["X-Enlace360-Agent-Secret"] = $AgentSecret

# ============================================================================
# FUNCIONES DE RED
# ============================================================================

Function Get-LocalIP {
    $ip = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet*","Wi-Fi*" -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notmatch "^169\.254\." } | Select-Object -First 1 -ExpandProperty IPAddress
    if ($ip) { return $ip } else { return "Desconocida" }
}

Function Get-LocalMAC {
    $mac = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq "Up" | Select-Object -First 1 -ExpandProperty MacAddress
    if ($mac) { return $mac -replace '-',':' } else { return "Desconocida" }
}

Function Test-InternetConnection {
    try {
        $result = Invoke-WithTimeout -TimeoutSeconds 8 -ScriptBlock {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

            $testGstatic = Invoke-WebRequest -Uri "http://www.gstatic.com/generate_204" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
            if ($testGstatic -and $testGstatic.StatusCode -eq 204) { return @{ IsOnline = $true; Latency = 0 } }

            $pingGoogle = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue
            if ($pingGoogle) {
                $fullPing = Test-Connection -ComputerName "8.8.8.8" -Count 1 -ErrorAction SilentlyContinue
                return @{ IsOnline = $true; Latency = $fullPing.ResponseTime }
            }
            return @{ IsOnline = $false; Latency = 0 }
        }

        $result = @($result) | Select-Object -Last 1
        if ($result -is [hashtable]) {
            return @{ IsOnline = [bool]$result["IsOnline"]; Latency = [int]$result["Latency"] }
        }
        return @{ IsOnline = [bool]$result.IsOnline; Latency = [int]$result.Latency }
    } catch {
        Write-Log "[WARNING] Test-InternetConnection fallo/timeout: $($_.Exception.Message)"
        return @{ IsOnline = $false; Latency = 0 }
    }
}

Function Get-SystemUptime {
    try {
        $os = Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5
        $uptime = (Get-Date) - $os.LastBootUpTime
        return "{0} d, {1} h, {2} m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
    } catch { return "Desconocido" }
}

Function New-IntegrityCheck {
    param(
        [string]$Name,
        [string]$Kind,
        [bool]$Ok,
        [string]$Severity,
        [string]$Details
    )

    [pscustomobject]@{
        name = $Name
        kind = $Kind
        ok = $Ok
        severity = $Severity
        details = $Details
    }
}

Function Get-FileIntegrityCheck {
    param(
        [string]$Name,
        [string]$Path,
        [string]$Severity = "critical"
    )

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        try {
            $hash = (Get-FileHash -LiteralPath $Path -Algorithm MD5 -ErrorAction Stop).Hash
            return New-IntegrityCheck -Name $Name -Kind "file" -Ok $true -Severity "ok" -Details "present hash=$hash"
        } catch {
            return New-IntegrityCheck -Name $Name -Kind "file" -Ok $true -Severity "warning" -Details "present hash_error=$($_.Exception.Message)"
        }
    }

    return New-IntegrityCheck -Name $Name -Kind "file" -Ok $false -Severity $Severity -Details "missing path=$Path"
}

Function Get-TaskIntegrityCheck {
    param(
        [string]$Name,
        [string]$Severity = "warning"
    )

    $task = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if ($task) {
        $info = Get-ScheduledTaskInfo -TaskName $Name -ErrorAction SilentlyContinue
        return New-IntegrityCheck -Name $Name -Kind "task" -Ok $true -Severity "ok" -Details "state=$($task.State); principal=$($task.Principal.UserId); last=$($info.LastTaskResult)"
    }

    return New-IntegrityCheck -Name $Name -Kind "task" -Ok $false -Severity $Severity -Details "missing scheduled_task=$Name"
}

Function Get-ServiceIntegrityCheck {
    param([string]$Name)

    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) {
        $severity = if ($svc.Status -eq "Running") { "ok" } else { "warning" }
        $svcInfo = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $Name) -ErrorAction SilentlyContinue
        return New-IntegrityCheck -Name $Name -Kind "service" -Ok ($svc.Status -eq "Running") -Severity $severity -Details "status=$($svc.Status); start_type=$($svcInfo.StartMode)"
    }

    return New-IntegrityCheck -Name $Name -Kind "service" -Ok $false -Severity "warning" -Details "missing windows_service=$Name"
}

Function Get-AgentIntegrity {
    $previousIntegrity = $null
    if (Test-Path -LiteralPath $IntegrityFile -PathType Leaf) {
        try { $previousIntegrity = Get-Content -LiteralPath $IntegrityFile -Raw | ConvertFrom-Json } catch { $previousIntegrity = $null }
    }

    $checks = @()
    $checks += Get-FileIntegrityCheck -Name "Agente_Enlace360_Service.ps1" -Path (Join-Path $LogDir "Agente_Enlace360_Service.ps1") -Severity "critical"
    $checks += Get-FileIntegrityCheck -Name "Enlace360_HealthCheck.ps1" -Path (Join-Path $LogDir "Enlace360_HealthCheck.ps1") -Severity "critical"
    $checks += Get-FileIntegrityCheck -Name "agent_payload.cache" -Path (Join-Path $LogDir "agent_payload.cache") -Severity "warning"
    $checks += Get-FileIntegrityCheck -Name "healthcheck_payload.cache" -Path (Join-Path $LogDir "healthcheck_payload.cache") -Severity "warning"
    $checks += Get-FileIntegrityCheck -Name "config.json" -Path $ConfigFile -Severity "critical"
    $checks += Get-FileIntegrityCheck -Name "install_manifest.json" -Path (Join-Path $LogDir "install_manifest.json") -Severity "warning"
    $checks += Get-TaskIntegrityCheck -Name $TaskAgent -Severity "warning"
    $checks += Get-TaskIntegrityCheck -Name $TaskHealthCheck -Severity "critical"
    $checks += Get-ServiceIntegrityCheck -Name $ServiceName

    $failed = @($checks | Where-Object { -not $_.ok })
    $critical = @($failed | Where-Object { $_.severity -eq "critical" })
    $warning = @($failed | Where-Object { $_.severity -ne "critical" })

    $status = "ok"
    if ($critical.Count -gt 0) {
        $status = "critical"
    } elseif ($warning.Count -gt 0) {
        $status = "warning"
    }

    $alert = if ($failed.Count -gt 0) {
        (($failed | ForEach-Object { "$($_.name): $($_.details)" }) -join " | ")
    } else {
        "Integridad OK"
    }

    $integrity = [pscustomobject]@{
        status = $status
        alert = $alert
        checked_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        service_name = $ServiceName
        expected_tasks = @($TaskAgent, $TaskHealthCheck)
        expected_files = @("Agente_Enlace360_Service.ps1", "Enlace360_HealthCheck.ps1", "agent_payload.cache", "healthcheck_payload.cache", "config.json", "install_manifest.json")
        failed_count = $failed.Count
        critical_count = $critical.Count
        warning_count = $warning.Count
        checks = $checks
    }

    if ($previousIntegrity -and $previousIntegrity.last_reported_fingerprint) {
        $integrity | Add-Member -NotePropertyName "last_reported_fingerprint" -NotePropertyValue $previousIntegrity.last_reported_fingerprint -Force
        $integrity | Add-Member -NotePropertyName "last_reported_at" -NotePropertyValue $previousIntegrity.last_reported_at -Force
    }

    try {
        $integrity | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $IntegrityFile -Encoding UTF8 -Force
    } catch {
        Write-Log "[WARNING] No se pudo escribir integrity_state.json: $($_.Exception.Message)"
    }

    return $integrity
}

Function Get-IntegrityFingerprint {
    param($Integrity)
    if (-not $Integrity -or $Integrity.status -eq "ok") { return "ok" }
    return (@($Integrity.checks) | Where-Object { -not $_.ok } | ForEach-Object { "$($_.kind):$($_.name):$($_.severity)" }) -join "|"
}

Function Report-IntegrityEvent {
    param($Integrity)
    if (-not $Integrity -or $Integrity.status -eq "ok") { return }

    $fingerprint = Get-IntegrityFingerprint -Integrity $Integrity
    $last = $null
    if (Test-Path -LiteralPath $IntegrityFile -PathType Leaf) {
        try { $last = Get-Content -LiteralPath $IntegrityFile -Raw | ConvertFrom-Json } catch { $last = $null }
    }

    if ($last -and $last.last_reported_fingerprint -eq $fingerprint -and $last.last_reported_at) {
        try {
            $lastReport = ([datetime]$last.last_reported_at).ToUniversalTime()
            if (((Get-Date).ToUniversalTime() - $lastReport).TotalHours -lt 6) { return }
        } catch {}
    }

    $nowUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $cause = "INTEGRIDAD AGENTE $($Integrity.status.ToUpper()): $($Integrity.alert)"
    if ($cause.Length -gt 500) { $cause = $cause.Substring(0, 500) + "...[Truncado]" }

    $bodyStr = @{
        kiosk_id = $KioskName
        client_name = $ClientName
        location = $Location
        offline_time = $nowUtc
        online_time = $nowUtc
        probable_cause = $cause
        diagnostics = $Integrity
    } | ConvertTo-Json -Depth 8

    $rpcBody = @{
        p_kiosk_id = $KioskName
        p_client_name = $ClientName
        p_location = $Location
        p_offline_time = $nowUtc
        p_online_time = $nowUtc
        p_probable_cause = $cause
        p_diagnostics = $Integrity
    } | ConvertTo-Json -Depth 8

    try {
        Send-RestRequest -Uri "$SupabaseUrl/rest/v1/rpc/enlace360_report_network_event" -Method "POST" -Headers $Headers -JsonBody $rpcBody | Out-Null
        Write-Log "[INTEGRITY] Evento de integridad reportado a Supabase: $fingerprint"
        $Integrity | Add-Member -NotePropertyName "last_reported_fingerprint" -NotePropertyValue $fingerprint -Force
        $Integrity | Add-Member -NotePropertyName "last_reported_at" -NotePropertyValue $nowUtc -Force
        $Integrity | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $IntegrityFile -Encoding UTF8 -Force
        return
    } catch {
        Write-Log "[WARNING] RPC de integridad no disponible/fallo. Reintentando REST legado: $_"
    }

    try {
        Send-RestRequest -Uri "$SupabaseUrl/rest/v1/network_events" -Method "POST" -Headers $Headers -JsonBody $bodyStr | Out-Null
        Write-Log "[INTEGRITY] Evento de integridad reportado a Supabase por REST legado: $fingerprint"
        $Integrity | Add-Member -NotePropertyName "last_reported_fingerprint" -NotePropertyValue $fingerprint -Force
        $Integrity | Add-Member -NotePropertyName "last_reported_at" -NotePropertyValue $nowUtc -Force
        $Integrity | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $IntegrityFile -Encoding UTF8 -Force
    } catch {
        Write-Log "[WARNING] No se pudo reportar evento de integridad: $_"
    }
}

Function Submit-KioskPayload {
    param([System.Collections.IDictionary]$Payload)

    $rpcBody = [ordered]@{
        p_kiosk_id = $Payload.kiosk_id
        p_client_name = $Payload.client_name
        p_location = $Payload.location
        p_status = $Payload.status
        p_last_heartbeat = $Payload.last_heartbeat
        p_uptime = $Payload.uptime
        p_ip_address = $Payload.ip_address
        p_mac_address = $Payload.mac_address
        p_latency_ms = $Payload.latency_ms
        p_integrity_status = $Payload.integrity_status
        p_integrity_alert = $Payload.integrity_alert
        p_integrity_checked_at = $Payload.integrity_checked_at
        p_integrity_details = $Payload.integrity_details
        p_agent_secret_hash = Get-Sha256Hex -Text $AgentSecret
    }

    try {
        Send-RestRequest -Uri "$SupabaseUrl/rest/v1/rpc/enlace360_submit_kiosk_heartbeat" -Method "POST" -Headers $Headers -JsonBody ($rpcBody | ConvertTo-Json -Depth 8) | Out-Null
        return $true
    } catch {
        Write-Log "[WARNING] RPC heartbeat seguro no disponible/fallo. Reintentando REST legado: $_"
    }

    $headersUpsert = $Headers.Clone()
    $headersUpsert.Add("Prefer", "resolution=merge-duplicates")
    $url = "$SupabaseUrl/rest/v1/kiosks"

    try {
        Send-RestRequest -Uri $url -Method "POST" -Headers $headersUpsert -JsonBody ($Payload | ConvertTo-Json -Depth 8) | Out-Null
        return $true
    } catch {
        $errorText = [string]$_
        if ($Payload.Contains("integrity_status") -and ($errorText -match "integrity_|schema cache|PGRST|column")) {
            Write-Log "[WARNING] Supabase aun no acepta columnas de integridad. Reintentando heartbeat base: $errorText"
            $fallback = $Payload.Clone()
            foreach ($key in @("integrity_status", "integrity_alert", "integrity_checked_at", "integrity_details")) {
                if ($fallback.Contains($key)) { $fallback.Remove($key) }
            }
            Send-RestRequest -Uri $url -Method "POST" -Headers $headersUpsert -JsonBody ($fallback | ConvertTo-Json -Depth 5) | Out-Null
            return $true
        }
        throw
    }
}

# Auto-UpdateFromGitHub eliminada en v3.4.
# La actualizacion ahora se gestiona via C2 (boton 'Actualizar Agente' en el Dashboard)
# + deteccion automatica de cambios en disco via Check-SelfUpdate (hash MD5).

# ============================================================================
# FUNCIONES DE SUPABASE Y C2
# ============================================================================

Function Update-KioskStatus {
    param([string]$Status, [int]$Latency = 0)
    try {
        Write-Log "[HEARTBEAT] Preparando payload ($Status)..."

        $upStr = Get-SystemUptime
        $upFinal = $upStr + " | " + $AgentVersion
        $localIp = Get-LocalIP
        $localMac = Get-LocalMAC
        $integrity = Get-AgentIntegrity

        $payload = [ordered]@{
            kiosk_id = $KioskName
            client_name = $ClientName
            location = $Location
            status = $Status
            last_heartbeat = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            uptime = $upFinal
            ip_address = $localIp
            mac_address = $localMac
            latency_ms = $Latency
            updated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            integrity_status = $integrity.status
            integrity_alert = $integrity.alert
            integrity_checked_at = $integrity.checked_at
            integrity_details = $integrity
        }

        Write-Log "[HEARTBEAT] Enviando estado ($Status) a Supabase..."
        Submit-KioskPayload -Payload $payload | Out-Null
        Write-Log "Estado ($Status) actualizado en Supabase."
        Report-IntegrityEvent -Integrity $integrity
        return $true
    } catch {
        Write-Log "[WARNING] No se pudo actualizar estado en Supabase: $_"
        return $false
    }
}

Function Check-RemoteCommands {
    # status=eq.pending ahora se filtra dentro de enlace360_claim_remote_commands.
    $url = "$SupabaseUrl/rest/v1/rpc/enlace360_claim_remote_commands"
    $claimBody = @{
        p_kiosk_id = $KioskName
        p_limit = 5
    } | ConvertTo-Json

    try {
        $commandsRaw = Invoke-EnlaceRestJson -Uri $url -Method "POST" -Headers $Headers -JsonBody $claimBody
        if ($null -eq $commandsRaw) { return }
        $commands = @($commandsRaw)
        if ($commands.Count -gt 0) {
            Write-Log "[TERMINAL C2] $($commands.Count) comando(s) reclamado(s) por RPC seguro."
        }

        foreach ($cmd in $commands) {
            Write-Log "[TERMINAL C2] Ejecutando orden remota: $($cmd.command_string)"

            [string]$output = ""
            $execStatus = "executed"

            # Ejecucion aislada con Timeout (Evita cuelgues del demonio)
            try {
                $job = Start-Job -ScriptBlock { Invoke-Expression $args[0] 2>&1 | Out-String } -ArgumentList $cmd.command_string
                $jobCompleted = Wait-Job -Job $job -Timeout 60

                if ($jobCompleted) {
                    $output = [string](Receive-Job -Job $job)
                } else {
                    Stop-Job -Job $job
                    $output = "[ERROR DE SEGURIDAD] Comando abortado por el Agente. Excedio el limite maximo de 60 segundos (Posible bucle infinito o comando interactivo)."
                    $execStatus = "failed"
                    Write-Log $output
                }
                Remove-Job -Job $job -Force
            } catch {
                $output = $_.Exception.Message
                $execStatus = "failed"
            }

            if ([string]::IsNullOrWhiteSpace($output)) { $output = "Comando ejecutado sin salida (Success)." }
            if ($output.Length -gt 4000) { $output = $output.Substring(0, 4000) + "...[Truncado]" }

            $bodyStr = @{
                p_command_id = $cmd.id
                p_kiosk_id = $KioskName
                p_status = $execStatus
                p_output_log = $output.Trim()
            } | ConvertTo-Json

            try {
                Send-RestRequest -Uri "$SupabaseUrl/rest/v1/rpc/enlace360_complete_remote_command" -Method "POST" -Headers $Headers -JsonBody $bodyStr | Out-Null
                Write-Log "[TERMINAL C2] Comando reportado a Supabase por RPC seguro."
            } catch {
                Write-Log "[WARNING] Fallo al devolver log a Supabase. Error: $_"
            }
        }
    } catch {
        Write-Log "[WARNING] Fallo consultando comandos remotos por RPC seguro: $_"
    }
}

Function Report-NetworkIncident {
    param($OfflineTime, $OnlineTime, $Cause, $DiagnosticsObj)
    $url = "$SupabaseUrl/rest/v1/network_events"

    $offUtc = (Get-Date $OfflineTime).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $onUtc = (Get-Date $OnlineTime).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    $bodyStr = @{
        kiosk_id = $KioskName
        client_name = $ClientName
        location = $Location
        offline_time = $offUtc
        online_time = $onUtc
        probable_cause = $Cause
        diagnostics = $DiagnosticsObj
    } | ConvertTo-Json -Depth 5

    $rpcBody = @{
        p_kiosk_id = $KioskName
        p_client_name = $ClientName
        p_location = $Location
        p_offline_time = $offUtc
        p_online_time = $onUtc
        p_probable_cause = $Cause
        p_diagnostics = $DiagnosticsObj
    } | ConvertTo-Json -Depth 5

    try {
        Send-RestRequest -Uri "$SupabaseUrl/rest/v1/rpc/enlace360_report_network_event" -Method "POST" -Headers $Headers -JsonBody $rpcBody | Out-Null
        Write-Log "Incidente de red reportado a Supabase por RPC seguro."
        return $true
    } catch {
        Write-Log "[WARNING] RPC de incidente no disponible/fallo. Reintentando REST legado: $_"
    }

    try {
        Send-RestRequest -Uri $url -Method "POST" -Headers $Headers -JsonBody $bodyStr | Out-Null
        Write-Log "Incidente de red reportado a Supabase por REST legado."
        return $true
    } catch {
        Write-Log "[ERROR] Fallo reportando incidente: $_"
        return $false
    }
}

Function Attempt-SelfHealing {
    Write-Log "[HEAL] Intento 1: Limpiando cache DNS..."
    ipconfig /flushdns | Out-Null
    Start-Sleep -Seconds 3
    if ((Test-InternetConnection).IsOnline) { return $true }

    Write-Log "[HEAL] Intento 2: Reiniciando Adaptador Fisico..."
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Restart-NetAdapter -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 12
    if ((Test-InternetConnection).IsOnline) { return $true }

    return $false
}

Function Collect-Diagnostics {
    $diag = @{}
    $diag.Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $diag.Uptime = Get-SystemUptime
    $diag.Adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Select-Object Name, InterfaceDescription, Status, LinkSpeed)

    $ipConfig = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null } | Select-Object -First 1
    if ($ipConfig) {
        $diag.GatewayIP = $ipConfig.IPv4DefaultGateway.NextHop
        $diag.DnsServers = ($ipConfig.DNSServer | Select-Object -ExpandProperty ServerAddresses) -join ", "
        $diag.GatewayReachable = Test-Connection -ComputerName $diag.GatewayIP -Count 1 -Quiet -ErrorAction SilentlyContinue
    } else {
        $diag.GatewayIP = "No encontrado"
        $diag.DnsServers = "No encontrados"
        $diag.GatewayReachable = $false
    }

    $diag.InternetIpReachable = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue

    try {
        $null = Resolve-DnsName "google.com" -ErrorAction Stop
        $diag.DnsResolutionOk = $true
    } catch {
        $diag.DnsResolutionOk = $false
    }

    return $diag
}

Function Analyze-Fault {
    param($OfflineDiag)
    $cause = "Desconocida"
    $adaptersStatus = $OfflineDiag.Adapters | Select-Object -ExpandProperty Status

    if ($adaptersStatus -contains "Disconnected" -or $adaptersStatus -contains "Not Present") {
        $cause = "CABLE DESCONECTADO O PUERTO APAGADO (Falla de Capa 1)"
    } elseif (-not $OfflineDiag.GatewayReachable) {
        if ($OfflineDiag.GatewayIP -ne "No encontrado") {
            $cause = "GATEWAY INACCESIBLE. Posible falla del switch o router local."
        } else {
            $cause = "SIN GATEWAY / SIN DHCP. El equipo no pudo obtener una IP local."
        }
    } elseif (-not $OfflineDiag.InternetIpReachable) {
        $cause = "SIN SALIDA A INTERNET. Falla del ISP (Proveedor de Internet) del cliente."
    } elseif (-not $OfflineDiag.DnsResolutionOk) {
        $cause = "FALLA DE DNS. Internet funciona por IP, pero el servidor DNS del cliente ($($OfflineDiag.DnsServers)) falla."
    } else {
        $cause = "BLOQUEO DE RED/FIREWALL HACIA PLATAFORMA. La red basica funciona bien."
    }

    return $cause
}

Function Check-Heartbeat {
    $now = Get-Date
    $lastHeartbeatTime = $null
    if (Test-Path $HeartbeatFile) {
        try {
            $fileContent = Get-Content $HeartbeatFile -Raw
            $lastHeartbeatTime = [datetime]$fileContent
        } catch { }
    }

    if (-not $lastHeartbeatTime -or ($now - $lastHeartbeatTime).TotalMinutes -ge 2) {
        $updated = Update-KioskStatus -Status "online" -Latency 0
        if (-not $updated) {
            Write-Log "[HEARTBEAT] No se actualiza last_heartbeat local porque Supabase no confirmo."
            return
        }
        $now.ToString("yyyy-MM-dd HH:mm:ss") | Set-Content $HeartbeatFile
    }
}

# ============================================================================
# BUCLE PRINCIPAL (MODO DEMONIO ENTERPRISE)
# ============================================================================
Write-Log "=== INICIANDO AGENTE ENLACE360 ($AgentVersion) EN MODO DEMONIO ==="
Write-Log "Kiosco: $KioskName | Ubicacion: $Location | Cliente: $ClientName"

$StartupHash = (Get-FileHash $ScriptPath -Algorithm MD5).Hash
Write-Log "Hash de arranque: $StartupHash"

Function Check-SelfUpdate {
    try {
        $currentHash = (Get-FileHash $ScriptPath -Algorithm MD5).Hash
        if ($currentHash -ne $StartupHash) {
            Write-Log "[UPDATE] Archivo del agente modificado (Hash cambio de $StartupHash a $currentHash). Aplicando hot-swap..."
            Update-KioskStatus -Status "online"
            $restartCmd = "Start-Sleep -Seconds 3; Stop-ScheduledTask -TaskName 'Enlace360_Agent' -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2; Start-ScheduledTask -TaskName 'Enlace360_Agent'"
            Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -Command `"$restartCmd`""
            Write-Log "[UPDATE] Proceso de reinicio lanzado. Cerrando version antigua..."
            Exit
        }
    } catch {}
}

Update-KioskStatus -Status "online"

$isOnline = $true
$offlineData = $null

if (Test-Path $StateFile) {
    try {
        $savedState = Get-Content $StateFile -Raw | ConvertFrom-Json
        if ($savedState.Status -eq "OFFLINE") {
            $isOnline = $false
            $offlineData = $savedState.Diagnostics
            Write-Log "Recuperado estado previo: OFFLINE."
        }
    } catch {
        Write-Log "[WARNING] network_state.json estaba corrupto. Se ignora."
        Remove-Item $StateFile -Force -ErrorAction SilentlyContinue
    }
}

while ($true) {
    try {
        Check-Heartbeat
        Check-RemoteCommands
        Check-SelfUpdate

        $netStatus = Test-InternetConnection
        $pingSuccess = $netStatus.IsOnline
        $currentLatency = $netStatus.Latency

        if (-not $pingSuccess -and $isOnline) {
            Write-Log "[ALERTA] Conexion de red perdida. Activando auto-reparacion..."
            $healed = Attempt-SelfHealing

            if ($healed) {
                Write-Log "[INFO] Auto-reparacion local exitosa (Micro-corte mitigado)."
                $now = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                Report-NetworkIncident -OfflineTime $now -OnlineTime $now -Cause "AUTO-REPARADO (Micro-corte)" -DiagnosticsObj @{}
            } else {
                Write-Log "[ALERTA] Auto-reparacion fallida. Transicionando a modo OFFLINE."
                $isOnline = $false
                Update-KioskStatus -Status "offline" | Out-Null
                $offlineData = Collect-Diagnostics
                try {
                    @{ Status = "OFFLINE"; OfflineTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"); Diagnostics = $offlineData } | ConvertTo-Json -Depth 5 | Set-Content $StateFile
                } catch { Write-Log "[ERROR] Imposible guardar network_state.json" }
            }
        }
        elseif ($pingSuccess -and -not $isOnline) {
            $recoveryTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Write-Log "[INFO] Red detectada nuevamente. Estabilizando (10s)..."
            Start-Sleep -Seconds 10

            $reportSuccess = $true
            if ($offlineData) {
                $probableCause = Analyze-Fault -OfflineDiag $offlineData
                Write-Log "[INFO] Causa probable analizada: $probableCause"
                $reportSuccess = Report-NetworkIncident -OfflineTime $offlineData.Timestamp -OnlineTime $recoveryTime -Cause $probableCause -DiagnosticsObj $offlineData
            }

            if ($reportSuccess) {
                $isOnline = $true
                try { @{ Status = "ONLINE" } | ConvertTo-Json | Set-Content $StateFile } catch {}
                Update-KioskStatus -Status "online" -Latency $currentLatency | Out-Null
                Write-Log "[INFO] Incidente cerrado y reportado. Kiosco 100% operativo."
            }
        }
        elseif (-not $pingSuccess -and -not $isOnline) {
            if ($offlineData -and $offlineData.Timestamp) {
                try {
                    $offlineStart = [datetime]$offlineData.Timestamp
                    if (((Get-Date) - $offlineStart).TotalHours -ge 1) {
                        # Verificar limite de reinicios Lazaro (max 3 por dia)
                        $lazaroFile = Join-Path $LogDir "lazaro_count.txt"
                        $lazaroCount = 0
                        $lazaroDate = ""
                        if (Test-Path $lazaroFile) {
                            try {
                                $lazData = Get-Content $lazaroFile -Raw | ConvertFrom-Json
                                $lazaroDate = $lazData.Date
                                $lazaroCount = [int]$lazData.Count
                            } catch {}
                        }
                        $today = (Get-Date).ToString("yyyy-MM-dd")
                        if ($lazaroDate -ne $today) { $lazaroCount = 0 }

                        if ($lazaroCount -lt 3) {
                            $lazaroCount++
                            @{ Date = $today; Count = $lazaroCount } | ConvertTo-Json | Set-Content $lazaroFile
                            Write-Log "[CRITICO] Protocolo Lazaro ($lazaroCount/3 hoy). Reinicio forzado..."
                            Update-KioskStatus -Status "offline" | Out-Null
                            Restart-Computer -Force
                        } else {
                            Write-Log "[CRITICO] Lazaro agotado (3/3 reinicios hoy). Esperando al dia siguiente."
                        }
                    }
                } catch {}
            }
        }
    } catch {
        Write-Log "[ERROR] Error inesperado en bucle principal: $_"
    }

    Start-Sleep -Seconds $CheckIntervalSecs
}
