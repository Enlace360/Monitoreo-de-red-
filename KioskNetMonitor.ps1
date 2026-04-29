<#
.SYNOPSIS
    Kiosk Network Monitor - Agente de monitoreo de red (Versión Mejorada).
.DESCRIPTION
    Monitorea la conexión a internet.
    - Intenta auto-repararse si se pierde la conexión.
    - Guarda un registro histórico en CSV.
    - Envía una señal de vida (Heartbeat) diaria.
#>

# ============================================================================
# CONFIGURACIÓN (Modificar según sea necesario)
# ============================================================================
$ClientName = "NombreDelCliente"
$KioskName = $env:COMPUTERNAME

# Configuración de Correo (SMTP)
$SmtpServer = "smtp.gmail.com"
$SmtpPort = 587
$SmtpUser = "tu_correo@gmail.com"
$SmtpPass = "tu_password_de_aplicacion" 
$FromAddress = "alertas_kioscos@tuempresa.com"
$ToAddress = "soporte@tuempresa.com"

# Configuración de Monitoreo
$TargetPing = "8.8.8.8"      # IP para verificar salida a internet
$CheckIntervalSecs = 30      # Cada cuántos segundos revisar
$LogDir = "C:\KioskNetMonitor"

# Modo Prueba (Para probar en Windows sin desconectar el cable)
$ForceTestEmail = $false     

# ============================================================================
# INICIALIZACIÓN Y ARCHIVOS
# ============================================================================
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$StateFile = Join-Path $LogDir "network_state.json"
$CsvFile = Join-Path $LogDir "historial_caidas.csv"
$HeartbeatFile = Join-Path $LogDir "last_heartbeat.txt"
$HeartbeatHour = 8 # Hora a la que se envía el reporte de vida (0-23)

# Funciones Auxiliares
Function Get-DefaultGateway {
    try {
        $routes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
        if ($routes) { return $routes[0].NextHop }
    } catch {}
    return $null
}

Function Get-SystemUptime {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $uptime = (Get-Date) - $os.LastBootUpTime
        return "{0} días, {1} horas, {2} min" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
    } catch { return "Desconocido" }
}

Function Send-EmailAlert {
    param([string]$Subject, [string]$HtmlBody)
    $msg = New-Object System.Net.Mail.MailMessage
    $msg.From = $FromAddress
    $msg.To.Add($ToAddress)
    $msg.Subject = $Subject
    $msg.Body = $HtmlBody
    $msg.IsBodyHtml = $true

    $smtp = New-Object System.Net.Mail.SmtpClient
    $smtp.Host = $SmtpServer
    $smtp.Port = $SmtpPort
    $smtp.EnableSsl = $true
    $smtp.Credentials = New-Object System.Net.NetworkCredential($SmtpUser, $SmtpPass)
    
    try {
        $smtp.Send($msg)
        Write-Output "$(Get-Date): Correo enviado exitosamente: $Subject"
    } catch {
        Write-Error "Error enviando correo: $_"
    }
}

Function Log-ToCSV {
    param($OfflineTime, $OnlineTime, $Cause)
    if (-not (Test-Path $CsvFile)) {
        "KioskName,ClientName,OfflineTime,OnlineTime,ProbableCause" | Out-File -FilePath $CsvFile -Encoding UTF8
    }
    $line = "`"$KioskName`",`"$ClientName`",`"$OfflineTime`",`"$OnlineTime`",`"$Cause`""
    $line | Out-File -FilePath $CsvFile -Append -Encoding UTF8
}

Function Attempt-SelfHealing {
    Write-Output "Intento 1: Renovando IP (ipconfig /renew)..."
    ipconfig /renew | Out-Null
    Start-Sleep -Seconds 5
    if (Test-Connection -ComputerName $TargetPing -Count 1 -Quiet -ErrorAction SilentlyContinue) { return $true }
    
    Write-Output "Intento 2: Reiniciando Adaptador Físico..."
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Restart-NetAdapter -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 12 # Dar tiempo a que el hardware encienda y negocie red
    if (Test-Connection -ComputerName $TargetPing -Count 1 -Quiet -ErrorAction SilentlyContinue) { return $true }
    
    return $false
}

Function Collect-Diagnostics {
    $diag = @{}
    $diag.Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $diag.Uptime = Get-SystemUptime
    $diag.Adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Select-Object Name, InterfaceDescription, Status, LinkSpeed
    $gateway = Get-DefaultGateway
    if ($gateway) {
        $diag.GatewayIP = $gateway
        $diag.GatewayReachable = Test-Connection -ComputerName $gateway -Count 1 -Quiet -ErrorAction SilentlyContinue
    } else {
        $diag.GatewayIP = "No encontrado"
        $diag.GatewayReachable = $false
    }
    $diag.IPConfig = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -ne "Loopback Pseudo-Interface 1" } | Select-Object InterfaceAlias, IPAddress
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
            $cause = "SIN GATEWAY / SIN DHCP. El equipo no obtuvo IP válida del router."
        }
    } else {
        $cause = "FALLA DE INTERNET/ISP. El equipo llega al router local, pero no a Internet."
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
            $subject = "💚 SEÑAL DE VIDA: $ClientName - $KioskName"
            $htmlBody = @"
            <html><body style='font-family: Arial; padding: 20px;'>
                <h2 style='color: #5cb85c;'>✅ Kiosco Activo y Monitoreando</h2>
                <p>El equipo <strong>$KioskName</strong> ($ClientName) está en línea y funcionando correctamente.</p>
                <ul>
                    <li><strong>Tiempo encendido (Uptime):</strong> $(Get-SystemUptime)</li>
                    <li><strong>Última revisión:</strong> $(Get-Date)</li>
                </ul>
                <p style='color: #777; font-size: 12px;'>Este es un reporte automático diario generado a las $HeartbeatHour:00.</p>
            </body></html>
"@
            Send-EmailAlert -Subject $subject -HtmlBody $htmlBody
            $todayStr | Set-Content $HeartbeatFile
        }
    }
}

# ============================================================================
# BUCLE PRINCIPAL
# ============================================================================
Write-Output "Iniciando monitor en $KioskName ($ClientName)..."

# Lógica de simulación (si aplica)
if ($ForceTestEmail) {
    # [El código de simulación permanece oculto por brevedad, envía un correo simulado como antes]
    Write-Output "⚠️ MODO PRUEBA ACTIVADO. Generando alerta..."
    # Simulamos un diagnóstico para probar que el envío funciona
    $fakeDiag = @{ Timestamp = (Get-Date).AddMinutes(-5).ToString("yyyy-MM-dd HH:mm:ss"); Uptime = "14 días"; Adapters = @(@{ Name = "Ethernet"; InterfaceDescription = "Intel"; Status = "Disconnected" }); GatewayIP = "192.168.1.1"; GatewayReachable = $false }
    $probableCause = Analyze-Fault -OfflineDiag $fakeDiag
    Send-EmailAlert -Subject "[PRUEBA] ⚠️ REPORTE DE CAÍDA" -HtmlBody "<h3>Causa: $probableCause</h3><p>Prueba de correo mejorado.</p>"
    exit
}

# Estado inicial
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
            Write-Output "$(Get-Date): Auto-reparación exitosa. Evitando alerta."
            Log-ToCSV -OfflineTime (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") -OnlineTime (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") -Cause "AUTO-REPARADO (Micro-corte)"
        } else {
            $isOnline = $false
            Write-Output "$(Get-Date): RED PERDIDA (Definitiva). Recolectando diagnósticos..."
            
            $offlineData = Collect-Diagnostics
            @{ Status = "OFFLINE"; OfflineTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"); Diagnostics = $offlineData } | ConvertTo-Json -Depth 5 | Set-Content $StateFile
        }
    }
    elseif ($pingSuccess -and -not $isOnline) {
        $isOnline = $true
        $recoveryTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Write-Output "$recoveryTime: RED RESTABLECIDA. Procesando reporte..."
        
        @{ Status = "ONLINE" } | ConvertTo-Json | Set-Content $StateFile
        
        if ($offlineData) {
            $probableCause = Analyze-Fault -OfflineDiag $offlineData
            
            # Registrar en bitácora local
            Log-ToCSV -OfflineTime $offlineData.Timestamp -OnlineTime $recoveryTime -Cause $probableCause
            
            # Formatear adaptadores
            $adapterHtml = "<ul>"
            foreach ($a in $offlineData.Adapters) {
                $statusColor = if ($a.Status -eq "Up") { "green" } else { "red" }
                $adapterHtml += "<li><strong>$($a.Name):</strong> $($a.InterfaceDescription) - Estado: <span style='color:$statusColor'>$($a.Status)</span></li>"
            }
            $adapterHtml += "</ul>"

            $subject = "⚠️ REPORTE DE CAÍDA DE RED: $ClientName - $KioskName"
            $htmlBody = @"
            <html>
            <body style='font-family: Arial, sans-serif; padding: 20px; color: #333;'>
                <h2 style='color: #d9534f;'>🚨 Alerta de Desconexión de Red</h2>
                <p>El equipo kiosco <strong>$KioskName</strong> perteneciente al cliente <strong>$ClientName</strong> sufrió una interrupción de conectividad.</p>
                <div style='background-color: #f9f9f9; padding: 15px; border-left: 5px solid #d9534f; margin-bottom: 20px;'>
                    <h3 style='margin-top: 0;'>Análisis de Causa Raíz Probable:</h3>
                    <p style='font-size: 16px; font-weight: bold; color: #c9302c;'>$probableCause</p>
                </div>
                <h3>⏱️ Tiempos del Evento</h3>
                <ul>
                    <li><strong>Momento de Desconexión:</strong> $($offlineData.Timestamp)</li>
                    <li><strong>Momento de Recuperación:</strong> $recoveryTime</li>
                </ul>
                <h3>🔍 Evidencia</h3>
                $adapterHtml
                <p><strong>Gateway IP:</strong> $($offlineData.GatewayIP) | <strong>Ping Exitoso:</strong> $(if($offlineData.GatewayReachable){"Sí"}else{"No"})</p>
                <p><strong>Uptime:</strong> $($offlineData.Uptime)</p>
            </body>
            </html>
"@
            Send-EmailAlert -Subject $subject -HtmlBody $htmlBody
        }
    }
    
    Start-Sleep -Seconds $CheckIntervalSecs
}
