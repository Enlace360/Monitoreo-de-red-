<#
.SYNOPSIS
    Kiosk Network Monitor - Agente Supabase
.DESCRIPTION
    Monitorea la conexión a internet y reporta directamente a una base de datos 
    en Supabase vía API REST, eliminando la necesidad de enviar correos.
#>

# ============================================================================
# CONFIGURACIÓN (Supabase)
# ============================================================================
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ClientName = "Cencosud"
$Location = "Mall Costanera Center" # NUEVO: Sucursal o Ubicación del equipo
$KioskName = "NOMBRE_KIOSCO_AQUI"
$AgentVersion = "v1.1"

# Datos de tu proyecto Supabase (Obtén esto en Project Settings -> API)
$SupabaseUrl = "https://zhvykvpixpkjegfxgwer.supabase.co"
$SupabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpodnlrdnBpeHBramVnZnhnd2VyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc0ODI3NTksImV4cCI6MjA5MzA1ODc1OX0.kE0BA4IyldzvX4XfhF3bHAARTRDkAlqSgAlM6Am5YdI"

# Configuración de Monitoreo
$CheckIntervalSecs = 30      
$LogDir = "C:\KioskNetMonitor"

# ============================================================================
# INICIALIZACIÓN Y ARCHIVOS
# ============================================================================
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, "Global\KioskNetMonitor", [ref]$createdNew)
if (-not $createdNew) {
    Write-Output "Ya hay otra instancia del monitor corriendo. Saliendo..."
    exit
}

if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$StateFile = Join-Path $LogDir "network_state.json"
$HeartbeatFile = Join-Path $LogDir "last_heartbeat.txt"
$HeartbeatHour = 8 

# Cabeceras comunes para Supabase
$Headers = @{
    "apikey" = $SupabaseAnonKey
    "Authorization" = "Bearer $SupabaseAnonKey"
    "Content-Type" = "application/json"
}

# Funciones Auxiliares
Function Get-DefaultGateway {
    try {
        $routes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
        if ($routes) { return $routes[0].NextHop }
    } catch {}
    return $null
}

Function Get-LocalIP {
    try {
        $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1
        if ($route) {
            $ip = Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($ip) { return $ip.IPAddress }
        }
        $ip = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch "^169\.254\." -and $_.InterfaceAlias -ne "Loopback Pseudo-Interface 1" } | Select-Object -First 1
        if ($ip) { return $ip.IPAddress }
    } catch {}
    return "Desconocida"
}

Function Get-LocalMAC {
    try {
        $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1
        if ($route) {
            $mac = (Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue).MacAddress
            if ($mac) { return $mac -replace '-',':' }
        }
        $mac = (Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.Virtual -eq $false } | Select-Object -First 1).MacAddress
        if ($mac) { return $mac -replace '-',':' }
    } catch {}
    return "Desconocida"
}

Function Test-InternetConnection {
    $ping1 = Test-Connection -ComputerName "8.8.8.8" -Count 2 -ErrorAction SilentlyContinue
    if ($ping1 -and $ping1.ResponseTime -ne $null) {
        $avgLatency = ($ping1.ResponseTime | Measure-Object -Average).Average
        return @{ IsOnline = $true; Latency = [math]::Round($avgLatency) }
    }
    
    $ping2 = Test-Connection -ComputerName "1.1.1.1" -Count 1 -ErrorAction SilentlyContinue
    if ($ping2 -and $ping2.ResponseTime -ne $null) {
        return @{ IsOnline = $true; Latency = $ping2.ResponseTime[0] }
    }
    
    try {
        $http = Invoke-WebRequest -Uri "http://gstatic.com/generate_204" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        if ($http.StatusCode -eq 204) { return @{ IsOnline = $true; Latency = 999 } }
    } catch {}
    
    return @{ IsOnline = $false; Latency = 0 }
}

Function Get-SystemUptime {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $uptime = (Get-Date) - $os.LastBootUpTime
        return "{0} días, {1} horas, {2} min" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
    } catch { return "Desconocido" }
}

Function Auto-UpdateFromGitHub {
    # Solo intenta actualizar si estamos conectados a internet
    $ping = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue
    if (-not $ping) { return }

    $rawUrl = "https://raw.githubusercontent.com/Enlace360/Monitoreo-de-red-/main/KioskNetMonitor_Supabase.ps1"
    try {
        $newCode = Invoke-RestMethod -Uri $rawUrl -UseBasicParsing -ErrorAction Stop
        $currentCode = Get-Content $MyInvocation.MyCommand.Path -Raw
        
        # Si hay internet pero el codigo es igual o el repo es privado (falla), no hacemos nada
        if ($newCode.Length -eq $currentCode.Length -or $newCode -match "404: Not Found") { return }

        # Si el nuevo código existe, inyectamos nuestras variables locales para no perder la identidad
        $newCode = $newCode -replace '\$ClientName\s*=\s*".*"', "`$ClientName = `"$ClientName`""
        $newCode = $newCode -replace '\$Location\s*=\s*".*"', "`$Location = `"$Location`""
        $newCode = $newCode -replace '\$KioskName\s*=\s*".*"', "`$KioskName = `"$KioskName`""

        # Sobreescribimos el archivo local
        $newCode | Set-Content $MyInvocation.MyCommand.Path -Force
        Write-Output "Auto-actualización desde GitHub exitosa."
    } catch {
        # Falla silenciosamente (ej. repo privado o GitHub caido)
    }
}

# ============================================================================
# FUNCIONES DE SUPABASE
# ============================================================================

Function Update-KioskStatus {
    param([string]$Status, [int]$Latency = 0)
    $url = "$SupabaseUrl/rest/v1/kiosks"
    
    $headersUpsert = $Headers.Clone()
    $headersUpsert.Add("Prefer", "resolution=merge-duplicates")

    $body = @{
        kiosk_id = $KioskName
        client_name = $ClientName
        location = $Location
        status = $Status
        last_heartbeat = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        uptime = Get-SystemUptime
        ip_address = Get-LocalIP
        mac_address = Get-LocalMAC
        latency_ms = $Latency
    } | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri $url -Method Post -Headers $headersUpsert -Body $body -ErrorAction Stop | Out-Null
        Write-Output "Estado ($Status) actualizado en Supabase."
    } catch {
        Write-Warning "No se pudo actualizar estado en Supabase: $_"
    }
}

Function Check-RemoteCommands {
    # Evita llamadas si no hay internet
    $ping = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue
    if (-not $ping) { return }

    $encodedKioskName = [uri]::EscapeDataString($KioskName)
    $url = "$SupabaseUrl/rest/v1/remote_commands?kiosk_id=eq.$encodedKioskName&status=eq.pending"
    try {
        $commands = Invoke-RestMethod -Uri $url -Method Get -Headers $Headers -ErrorAction Stop
        foreach ($cmd in $commands) {
            Write-Output "$(Get-Date): Ejecutando comando remoto: $($cmd.command_string)"
            
            $output = ""
            $execStatus = "executed"
            try {
                $output = Invoke-Expression $cmd.command_string 2>&1 | Out-String
            } catch {
                $output = $_.Exception.Message
                $execStatus = "failed"
            }

            if ($output.Length -gt 4000) { $output = $output.Substring(0, 4000) + "...[Truncado]" }
            
            $updateUrl = "$SupabaseUrl/rest/v1/remote_commands?id=eq.$($cmd.id)"
            $headersPatch = $Headers.Clone()
            $headersPatch.Add("Prefer", "return=minimal")
            
            $body = @{
                status = $execStatus
                output_log = $output.Trim()
                executed_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            } | ConvertTo-Json

            Invoke-RestMethod -Uri $updateUrl -Method Patch -Headers $headersPatch -Body $body -ErrorAction Stop | Out-Null
            Write-Output "$(Get-Date): Comando remoto completado y reportado."
        }
    } catch {
        # Falla silenciosa si no hay comandos o Supabase rechaza
    }
}

Function Report-NetworkIncident {
    param($OfflineTime, $OnlineTime, $Cause, $DiagnosticsObj)
    $url = "$SupabaseUrl/rest/v1/network_events"

    # Preparar fechas en UTC para la BD
    $offUtc = (Get-Date $OfflineTime).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $onUtc = (Get-Date $OnlineTime).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    $body = @{
        kiosk_id = $KioskName
        client_name = $ClientName
        location = $Location
        offline_time = $offUtc
        online_time = $onUtc
        probable_cause = $Cause
        diagnostics = $DiagnosticsObj
    } | ConvertTo-Json -Depth 5

    try {
        Invoke-RestMethod -Uri $url -Method Post -Headers $Headers -Body $body -ErrorAction Stop | Out-Null
        Write-Output "Incidente reportado exitosamente a Supabase."
        return $true
    } catch {
        Write-Error "Fallo reportando incidente a Supabase: $_"
        return $false
    }
}

# ============================================================================
# DIAGNÓSTICOS Y REPARACIÓN
# ============================================================================

Function Attempt-SelfHealing {
    Write-Output "Intento 1: Limpiando caché DNS (Flush DNS)..."
    ipconfig /flushdns | Out-Null
    Start-Sleep -Seconds 3
    if ((Test-InternetConnection).IsOnline) { return $true }
    
    Write-Output "Intento 2: Reiniciando Adaptador Físico..."
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
            $cause = "GATEWAY INACCESIBLE. Posible falla de switch/router del cliente."
        } else {
            $cause = "SIN GATEWAY / SIN DHCP. El equipo no obtuvo IP."
        }
    } elseif ($OfflineDiag.GatewayReachable -and -not $OfflineDiag.InternetIpReachable) {
        $cause = "SIN SALIDA A INTERNET. El router local responde perfectamente, pero el ISP del cliente está caído."
    } elseif ($OfflineDiag.InternetIpReachable -and -not $OfflineDiag.DnsResolutionOk) {
        $cause = "FALLA DE DNS. Internet funciona por IP, pero el servidor DNS del cliente ($($OfflineDiag.DnsServers)) falla."
    } else {
        $cause = "BLOQUEO DE RED/FIREWALL HACIA PLATAFORMA. La red básica funciona bien."
    }
    
    return $cause
}

Function Check-Heartbeat {
    $now = Get-Date
    $lastHeartbeatTime = $null
    if (Test-Path $HeartbeatFile) { 
        $fileContent = Get-Content $HeartbeatFile
        try { $lastHeartbeatTime = [datetime]$fileContent } catch {}
    }
    
    # Si no hay registro o han pasado 5 minutos o más
    if (-not $lastHeartbeatTime -or ($now - $lastHeartbeatTime).TotalMinutes -ge 5) {
        Write-Output "Enviando Latido (Heartbeat 5m) a Supabase..."
        Update-KioskStatus -Status "online" -Latency (Test-InternetConnection).Latency
        $now.ToString("yyyy-MM-dd HH:mm:ss") | Set-Content $HeartbeatFile
    }
}

# ============================================================================
# BUCLE PRINCIPAL
# ============================================================================
Write-Output "Iniciando monitor (API Supabase) en $KioskName..."

# Buscar actualizaciones silenciosas antes de empezar
Auto-UpdateFromGitHub

# Actualizamos estado inicial en la BD a Online apenas arranque
Update-KioskStatus -Status "online"

$isOnline = $true
$offlineData = $null

if (Test-Path $StateFile) {
    $savedState = Get-Content $StateFile | ConvertFrom-Json
    if ($savedState.Status -eq "OFFLINE") {
        $isOnline = $false
        $offlineData = $savedState.Diagnostics
        Write-Output "El equipo inició y estaba OFFLINE previamente."
    }
}

while ($true) {
    Check-Heartbeat
    Check-RemoteCommands
    
    $netStatus = Test-InternetConnection
    $pingSuccess = $netStatus.IsOnline
    $currentLatency = $netStatus.Latency
    
    if (-not $pingSuccess -and $isOnline) {
        Write-Output "$(Get-Date): Conexión perdida. Iniciando auto-reparación..."
        $healed = Attempt-SelfHealing
        
        if ($healed) {
            Write-Output "$(Get-Date): Auto-reparación exitosa."
            # Opcional: Reportar micro-corte reparado
            $now = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Report-NetworkIncident -OfflineTime $now -OnlineTime $now -Cause "AUTO-REPARADO (Micro-corte)" -DiagnosticsObj @{}
        } else {
            $isOnline = $false
            Write-Output "$(Get-Date): RED PERDIDA. Reportando a Supabase..."
            
            # Avisamos a Supabase que el kiosco cayó (esto puede fallar si no hay red, 
            # pero lo intentamos por si solo es caída de ping externo pero llega a Supabase)
            Update-KioskStatus -Status "offline"

            $offlineData = Collect-Diagnostics
            @{ Status = "OFFLINE"; OfflineTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"); Diagnostics = $offlineData } | ConvertTo-Json -Depth 5 | Set-Content $StateFile
        }
    }
    elseif ($pingSuccess -and -not $isOnline) {
        $recoveryTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Write-Output "$($recoveryTime): RED RESTABLECIDA. Estabilizando ruteo (10s)..."
        Start-Sleep -Seconds 10
        
        $reportSuccess = $true
        if ($offlineData) {
            $probableCause = Analyze-Fault -OfflineDiag $offlineData
            $reportSuccess = Report-NetworkIncident -OfflineTime $offlineData.Timestamp -OnlineTime $recoveryTime -Cause $probableCause -DiagnosticsObj $offlineData
        }
        
        if ($reportSuccess) {
            $isOnline = $true
            @{ Status = "ONLINE" } | ConvertTo-Json | Set-Content $StateFile
            Update-KioskStatus -Status "online" -Latency $currentLatency
            Write-Output "Incidente cerrado localmente."
        } else {
            Write-Output "Fallo al enviar el reporte. Se mantendrá el estado OFFLINE local para reintentar luego."
        }
    }
    elseif (-not $pingSuccess -and -not $isOnline) {
        # Protocolo Lázaro: Si lleva más de 1 hora desconectado, reinicio forzado
        if ($offlineData -and $offlineData.Timestamp) {
            try {
                $offlineStart = [datetime]$offlineData.Timestamp
                if (((Get-Date) - $offlineStart).TotalHours -ge 1) {
                    Write-Output "$(Get-Date): Protocolo Lázaro activado. Offline > 1 hrs. Reiniciando OS..."
                    Update-KioskStatus -Status "offline"
                    Restart-Computer -Force
                }
            } catch {}
        }
    }
    
    Start-Sleep -Seconds $CheckIntervalSecs
}
