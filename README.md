# Kiosk Command Center - Enlace 360

Este documento contiene la guía técnica definitiva para implementar, instalar y utilizar la plataforma de monitoreo de red desarrollada para los kioscos de Enlace 360.

---

## 🏗 Arquitectura de la Solución

El sistema funciona bajo una arquitectura **Serverless (Sin Servidor)** en tres capas:

1. **El Agente Local (PowerShell):** Se ejecuta de forma invisible en cada kiosco Windows. Actúa como el "médico" del equipo: monitorea los latidos de la red, intenta auto-reparar cortes, y si la red muere definitivamente, ejecuta un análisis forense exhaustivo.
2. **El Cerebro Central (Supabase / PostgreSQL):** Base de datos en la nube que recibe los "Pings" y los "Reportes de Incidentes" de los agentes mediante una API REST segura.
3. **La Torre de Control (React / Vite):** Dashboard web Premium de Enlace 360, diseñado para monitorear en tiempo real el estado de salud de todos los equipos agrupados por cliente y sucursal.

---

## 🛠 Paso 1: Configurar el Cerebro Central (Supabase)

Supabase es el servicio gratuito que guardará el historial de caídas de forma segura.

1. Crea una cuenta gratuita en [Supabase.com](https://supabase.com).
2. Crea un **Nuevo Proyecto**.
3. Ve a la sección **SQL Editor** en el menú izquierdo.
4. Abre el archivo `supabase_schema.sql` que está en esta carpeta, copia todo su contenido y pégalo en el editor de Supabase.
5. Presiona **Run**. Esto creará automáticamente las tablas `kiosks` y `network_events` con sus reglas de seguridad.
6. Ve a **Project Settings -> API**. Allí encontrarás la `Project URL` y la `anon public key`. Copia ambos valores, los necesitarás en los pasos siguientes.

---

## 💻 Paso 2: Configurar e Instalar los Agentes en los Kioscos

El agente debe instalarse en cada uno de los 100 equipos Windows.

### 2.1. Configuración del Script
Abre el archivo `KioskNetMonitor_Supabase.ps1` y edita las primeras líneas (Líneas 12 a 18):
```powershell
$ClientName = "Nombre Del Cliente"      # Ej: Cenco Malls
$Location = "Nombre De La Sucursal"     # Ej: Mall Costanera Center
$SupabaseUrl = "TU_URL_DE_SUPABASE"     # Ej: https://xxxx.supabase.co
$SupabaseAnonKey = "TU_LLAVE_ANONIMA"   # La llave kilométrica de Supabase
```

### 2.2. Instalación Silenciosa (Para que corra 24/7)
Para que el script corra en segundo plano siempre que el PC esté encendido, aunque se reinicie, debes crear una **Tarea Programada** en Windows. 
Abre PowerShell como **Administrador** en el kiosco y ejecuta esto para instalarlo (asumiendo que copiaste el script a `C:\KioskNetMonitor\`):

```powershell
$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument '-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\KioskNetMonitor\KioskNetMonitor_Supabase.ps1"'
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal
Register-ScheduledTask -TaskName "Enlace360-NetMonitor" -InputObject $task
Start-ScheduledTask -TaskName "Enlace360-NetMonitor"
```
*(A partir de ese momento, el equipo empezará a reportarse como "Online" en tu plataforma).*

---

## 🌐 Paso 3: Lanzar la Torre de Control (Dashboard)

El Dashboard está construido con React y Vite. 

### 3.1. Conexión a Base de Datos
Dentro de la carpeta `dashboard/`, crea un archivo llamado `.env` y pega tus credenciales de Supabase:
```env
VITE_SUPABASE_URL=https://tu-proyecto.supabase.co
VITE_SUPABASE_ANON_KEY=tu-llave-anonima
```

### 3.2. Ejecutar Localmente
Para correrlo en tu Mac y probarlo:
```bash
cd dashboard
npm install
npm run dev
```

### 3.3. Despliegue Público (Cloudflare Pages)
Para que tú y tu equipo puedan verlo en cualquier lado sin depender de tu Mac:
1. Sube todo el código de la carpeta `dashboard` a un repositorio privado en **GitHub**.
2. Entra a **Cloudflare Pages** y conéctalo a ese repositorio.
3. En la configuración de Cloudflare, establece:
   - Framework: `Vite` o `React`
   - Build command: `npm run build`
   - Build output directory: `dist`
   - **Environment Variables:** No olvides agregar aquí las dos variables de Supabase.

---

## 🛡 Guía de Defensa: Interpretando la Matriz Forense (El "Alibi")

Cuando un equipo pierde conexión y la recupera, el agente envía un reporte forense exhaustivo evaluando la red en 4 capas. Cuando el cliente culpe a tus kioscos, haz clic en el incidente en la web y busca el **Causa Raíz Probable**.

Aquí tienes cómo usar esa información a tu favor:

| Mensaje de Causa Raíz en el Dashboard | Lo que significa técnicamente | Qué decirle al cliente |
| :--- | :--- | :--- |
| **CABLE DESCONECTADO O PUERTO APAGADO (Falla de Capa 1)** | El PC de tu kiosco no detecta señal eléctrica en su puerto de red. | *"Estimado cliente, la tarjeta de red del equipo no recibe señal física. Por favor verifiquen si alguien desconectó el cable, si se dañó, o si el Switch al que está conectado se apagó."* |
| **GATEWAY INACCESIBLE** | El cable está conectado (hay link), pero el PC no puede hacer ping al router/switch principal de la red local. | *"El equipo tiene el cable bien conectado, pero su router (ej: 192.168.1.1) dejó de respondernos. Favor revisar la red local del Mall."* |
| **SIN SALIDA A INTERNET** | El PC llega al router, pero el ping público (8.8.8.8) falla. | *"El equipo llega a su router local sin problemas, pero el ISP de la sucursal perdió conectividad hacia el exterior."* |
| **FALLA DE DNS** | El internet por IP funciona, pero los servidores DNS entregados por el cliente fallaron al resolver 'google.com'. | *"Existe un bloqueo en los servidores DNS de la red, ya que el equipo tiene internet pero no logra resolver páginas web. Revisen su configuración de DNS/Firewall."* |
| **BLOQUEO HACIA PLATAFORMA** | Todo el internet y DNS funciona, pero Supabase no respondió. | *(En este caso, la responsabilidad puede ser tuya o de un Firewall estricto del cliente bloqueando URLs desconocidas).* |

---
**Nota final de diseño:** El Dashboard posee datos falsos (dummy data) configurados por defecto para poder visualizar la grilla de equipos sin conexión a la base de datos. Una vez que agregues el archivo `.env` con las credenciales reales, el sistema vaciará los datos de prueba y comenzará a mostrar la flota real de kioscos.
