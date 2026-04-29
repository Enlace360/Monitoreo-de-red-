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
$ClientName = "Cencosud"
$Location = "Mall Costanera Center" # NUEVO: Sucursal o Ubicación del equipo
$KioskName = $env:COMPUTERNAME

# Datos de tu proyecto Supabase (Obtén esto en Project Settings -> API)
$SupabaseUrl = "https://zhvykvpixpkjegfxgwer.supabase.co"
$SupabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpodnlrdnBpeHBramVnZnhnd2VyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc0ODI3NTksImV4cCI6MjA5MzA1ODc1OX0.kE0BA4IyldzvX4XfhF3bHAARTRDkAlqSgAlM6Am5YdI"

# Configuración de Monitoreo
$TargetPing = "8.8.8.8"      
$CheckIntervalSecs = 30      
$LogDir = "C:\KioskNetMonitor"

# ============================================================================
# INICIALIZACIÓN Y ARCHIVOS
# ============================================================================
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
        $ip = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -ne "Loopback Pseudo-Interface 1" } | Select-Object -First 1
        if ($ip) { return $ip.IPAddress }
    } catch {}
    return "Desconocida"
}

Function Get-SystemUptime {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $uptime = (Get-Date) - $os.LastBootUpTime
        return "{0} días, {1} horas, {2} min" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
    } catch { return "Desconocido" }
}

# ============================================================================
# FUNCIONES DE SUPABASE
# ============================================================================

Function Update-KioskStatus {
    param([string]$Status)
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
    } | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri $url -Method Post -Headers $headersUpsert -Body $body -ErrorAction Stop | Out-Null
        Write-Output "Estado ($Status) actualizado en Supabase."
    } catch {
        Write-Warning "No se pudo actualizar estado en Supabase: $_"
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
    } catch {
        Write-Error "Fallo reportando incidente a Supabase: $_"
    }
}

# ============================================================================
# DIAGNÓSTICOS Y REPARACIÓN
# ============================================================================

Function Attempt-SelfHealing {
    Write-Output "Intento 1: Renovando IP..."
    ipconfig /renew | Out-Null
    Start-Sleep -Seconds 5
    if (Test-Connection -ComputerName $TargetPing -Count 1 -Quiet -ErrorAction SilentlyContinue) { return $true }
    
    Write-Output "Intento 2: Reiniciando Adaptador Físico..."
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Restart-NetAdapter -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 12 
    if (Test-Connection -ComputerName $TargetPing -Count 1 -Quiet -ErrorAction SilentlyContinue) { return $true }
    
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
    if ($now.Hour -eq $HeartbeatHour) {
        $lastHeartbeat = ""
        if (Test-Path $HeartbeatFile) { $lastHeartbeat = Get-Content $HeartbeatFile }
        $todayStr = $now.ToString("yyyy-MM-dd")
        
        if ($lastHeartbeat -ne $todayStr) {
            Write-Output "Enviando Señal de Vida a Supabase..."
            Update-KioskStatus -Status "online"
            $todayStr | Set-Content $HeartbeatFile
        }
    }
}

# ============================================================================
# BUCLE PRINCIPAL
# ============================================================================
Write-Output "Iniciando monitor (API Supabase) en $KioskName..."

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
    
    $pingSuccess = Test-Connection -ComputerName $TargetPing -Count 1 -Quiet -ErrorAction SilentlyContinue
    
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
        $isOnline = $true
        $recoveryTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Write-Output "$recoveryTime: RED RESTABLECIDA. Procesando reporte..."
        
        @{ Status = "ONLINE" } | ConvertTo-Json | Set-Content $StateFile
        
        # Volver a poner en línea
        Update-KioskStatus -Status "online"

        if ($offlineData) {
            $probableCause = Analyze-Fault -OfflineDiag $offlineData
            # Enviar el evento histórico a la Base de Datos
            Report-NetworkIncident -OfflineTime $offlineData.Timestamp -OnlineTime $recoveryTime -Cause $probableCause -DiagnosticsObj $offlineData
        }
    }
    
    Start-Sleep -Seconds $CheckIntervalSecs
}
