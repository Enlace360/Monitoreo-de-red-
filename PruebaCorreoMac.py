import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from datetime import datetime
import getpass

print("=== Simulador de Alertas de Red para Mac ===")
print("Este script enviará un correo de prueba usando tus credenciales SMTP para que puedas ver cómo luce el reporte.\n")

# Configuración interactiva
smtp_server = input("Servidor SMTP (ej. smtp.gmail.com): ") or "smtp.gmail.com"
smtp_port = input("Puerto SMTP (ej. 587): ") or "587"
sender_email = input("Tu correo origen (ej. alertas@tuempresa.com): ")
sender_password = getpass.getpass("Tu contraseña (o App Password): ")
receiver_email = input("Correo destino (ej. soporte@tuempresa.com): ")

# Datos simulados
client_name = "Cliente_Prueba_Mac"
kiosk_name = "KIOSCO-TEST-01"
timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

html_body = f"""
<html>
<body style='font-family: Arial, sans-serif; padding: 20px; color: #333;'>
    <h2 style='color: #d9534f;'>🚨 Alerta de Desconexión de Red (SIMULACRO MAC)</h2>
    <p>El equipo kiosco <strong>{kiosk_name}</strong> perteneciente al cliente <strong>{client_name}</strong> sufrió una interrupción de conectividad.</p>
    
    <div style='background-color: #f9f9f9; padding: 15px; border-left: 5px solid #d9534f; margin-bottom: 20px;'>
        <h3 style='margin-top: 0;'>Análisis de Causa Raíz Probable:</h3>
        <p style='font-size: 16px; font-weight: bold; color: #c9302c;'>CABLE DESCONECTADO O PUERTO APAGADO (Falla de Capa 1)</p>
    </div>

    <h3>⏱️ Tiempos del Evento</h3>
    <ul>
        <li><strong>Momento de Desconexión:</strong> {timestamp}</li>
        <li><strong>Momento de Recuperación:</strong> {timestamp}</li>
    </ul>

    <h3>🔍 Evidencia y Diagnósticos Recolectados (Momento de la caída)</h3>
    <p><em>Esta información demuestra el estado del equipo en el momento exacto en que se perdió la red.</em></p>
    
    <h4>1. Estado de Adaptadores Físicos (Cables)</h4>
    <ul>
        <li><strong>Ethernet:</strong> Intel Gigabit Network Connection - Estado: <span style='color:red'>Disconnected</span></li>
    </ul>

    <h4>2. Conectividad Local</h4>
    <ul>
        <li><strong>IP del Gateway (Router local):</strong> 192.168.1.1</li>
        <li><strong>Ping al Gateway Exitoso:</strong> No</li>
    </ul>

    <h4>3. Estado del Sistema</h4>
    <ul>
        <li><strong>Uptime (Tiempo de actividad):</strong> 14 días, 3 horas, 12 min <br><em>(Demuestra que el equipo no fue reiniciado durante la caída)</em></li>
    </ul>
    
    <hr>
    <p style='font-size: 12px; color: #777;'>Este es un reporte automático de prueba generado desde Mac. No responder a este correo.</p>
</body>
</html>
"""

print("\nEnviando correo...")

try:
    # Crear el mensaje
    msg = MIMEMultipart()
    msg['From'] = sender_email
    msg['To'] = receiver_email
    msg['Subject'] = f"[PRUEBA MAC] ⚠️ REPORTE DE CAÍDA DE RED: {client_name} - {kiosk_name}"
    msg.attach(MIMEText(html_body, 'html'))

    # Conectar al servidor SMTP
    server = smtplib.SMTP(smtp_server, int(smtp_port))
    server.starttls()
    server.login(sender_email, sender_password)
    text = msg.as_string()
    server.sendmail(sender_email, receiver_email, text)
    server.quit()
    
    print("✅ ¡Correo enviado exitosamente! Revisa tu bandeja de entrada.")
except Exception as e:
    print(f"❌ Error al enviar el correo: {e}")
