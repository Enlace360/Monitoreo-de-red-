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
$AgentVersion = "v3.6"

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
    } catch {
        Write-Log "[ERROR] Archivo config.json corrupto. Usando valores por defecto."
        $ClientName = "Desconocido"
        $Location = "Sin Ubicacion"
        $KioskName = "KIOSCO-" + $env:COMPUTERNAME
    }
} else {
    $ClientName = "Desconocido"
    $Location = "Sin Ubicacion"
    $KioskName = "KIOSCO-" + $env:COMPUTERNAME
}

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
        $url = "$SupabaseUrl/rest/v1/kiosks"
        
        $headersUpsert = $Headers.Clone()
        $headersUpsert.Add("Prefer", "resolution=merge-duplicates")

        $upStr = Get-SystemUptime
        $upFinal = $upStr + " | " + $AgentVersion
        $localIp = Get-LocalIP
        $localMac = Get-LocalMAC

        $bodyStr = @{
            kiosk_id = $KioskName
            client_name = $ClientName
            location = $Location
            status = $Status
            last_heartbeat = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            uptime = $upFinal
            ip_address = $localIp
            mac_address = $localMac
            latency_ms = $Latency
        } | ConvertTo-Json

        Write-Log "[HEARTBEAT] Enviando estado ($Status) a Supabase..."
        Send-RestRequest -Uri $url -Method "POST" -Headers $headersUpsert -JsonBody $bodyStr | Out-Null
        Write-Log "Estado ($Status) actualizado en Supabase."
        return $true
    } catch {
        Write-Log "[WARNING] No se pudo actualizar estado en Supabase: $_"
        return $false
    }
}

Function Check-RemoteCommands {
    $encodedKioskName = [uri]::EscapeDataString($KioskName)
    $url = $SupabaseUrl + "/rest/v1/remote_commands?kiosk_id=eq." + $encodedKioskName + "&status=eq.pending"
    
    try {
        $commandsRaw = Invoke-EnlaceRestJson -Uri $url -Method "GET" -Headers $Headers
        if ($null -eq $commandsRaw) { return }
        $commands = @($commandsRaw)
        if ($commands.Count -gt 0) {
            Write-Log "[TERMINAL C2] $($commands.Count) comando(s) pendiente(s) detectado(s)."
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
            
            $updateUrl = "$SupabaseUrl/rest/v1/remote_commands?id=eq.$($cmd.id)"
            $headersPatch = $Headers.Clone()
            $headersPatch.Add("Prefer", "return=minimal")
            
            $bodyStr = @{
                status = $execStatus
                output_log = $output.Trim()
                executed_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            } | ConvertTo-Json

            try {
                Send-RestRequest -Uri $updateUrl -Method "PATCH" -Headers $headersPatch -JsonBody $bodyStr | Out-Null
                Write-Log "[TERMINAL C2] Comando reportado a Supabase."
            } catch {
                Write-Log "[WARNING] Fallo al devolver log a Supabase. Error: $_"
            }
        }
    } catch {
        Write-Log "[WARNING] Fallo consultando comandos remotos: $_"
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

    try {
        Send-RestRequest -Uri $url -Method "POST" -Headers $Headers -JsonBody $bodyStr | Out-Null
        Write-Log "Incidente de red reportado a Supabase."
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
