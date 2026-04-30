# 🗼 Torre de Control Enlace 360

La **Torre de Control** no es solo un monitor de red; es una plataforma de **Inteligencia de Infraestructura y Auto-Mantenimiento** diseñada específicamente para flotas distribuidas de kioscos Windows en entornos hostiles (como Malls o sucursales comerciales).

Su objetivo principal es eliminar los "falsos positivos", automatizar el trabajo de soporte técnico en terreno y proporcionar evidencia forense irrefutable frente a caídas causadas por los Proveedores de Internet (ISPs) de los clientes.

---

## 🚀 Virtudes Principales de la Arquitectura

### 1. Resiliencia Extrema (El Agente Inmortal)
A diferencia de los monitores tradicionales, el Agente Local está diseñado para sobrevivir a casi cualquier eventualidad:
- **Watchdog Integrado:** Si el proceso es cerrado accidentalmente, Windows lo reiniciará automáticamente hasta 999 veces en lapsos de un minuto.
- **Zero-Touch Auto-Updates:** El agente es capaz de descargar actualizaciones silenciosas de su propio código fuente desde GitHub en cada inicio. Esto permite cambiar su comportamiento de forma masiva en 100+ equipos sin necesidad de usar TeamViewer nunca más.
- **Mutex Anti-Clonación:** Protegido contra la duplicación de procesos en memoria RAM para evitar que el envío de datos sature la red.

### 2. Auto-Sanación (Self-Healing de 3 Fases)
Cuando un equipo pierde conexión, el agente no se rinde, sino que intenta revivir el kiosco de forma escalonada:
1. **Fase Lógica:** Limpieza profunda de la caché DNS (*FlushDNS*) adaptada para redes con IPs Fijas.
2. **Fase Física:** Si la red sigue caída, el agente "desenchufa y vuelve a enchufar" digitalmente la tarjeta de red de Windows.
3. **Protocolo "Lázaro":** Si el equipo lleva más de 1 hora continua completamente desconectado, el agente asume que el Kernel de Windows se congeló y dispara un comando de reinicio forzado del sistema operativo (Hard Reboot), evitando el despacho de un técnico a la sucursal.

### 3. Diagnóstico Forense de Red
Cuando ocurre una caída real y prolongada, el agente recopila un registro completo de la salud del equipo en todas las capas del modelo OSI antes de desconectarse. Esto permite saber exactamente **de quién es la culpa**:
- **Capa 1 (Física):** Detecta si el cable de red fue desconectado manualmente del equipo.
- **Gateway:** Detecta si el Router local del cliente dejó de responder o si no asignó IPs.
- **DNS / Firewall:** Evalúa si la IP responde pero existe un bloqueo interno de nombres de dominio o un proxy corporativo impidiendo el paso.

### 4. Inteligencia Anti-Amnesia (Gestión de Estados)
Las caídas de red a menudo interrumpen el envío de los propios reportes de caída. El agente incluye una "Memoria Persistente":
- Si el internet se corta, el agente anota el incidente en su disco duro local.
- Cuando el internet regresa, el agente **espera inteligentemente 10 segundos** para permitir que las rutas TCP y los DNS se estabilicen completamente.
- Luego intenta enviar el reporte. Si la base de datos no responde por intermitencia de red, el agente se niega a olvidar el problema y reintenta infinitamente cada 30 segundos hasta asegurar que el evento llegó a la Torre de Control.

### 5. Monitor de Calidad (QoS) y Verificación Multi-Punto
Para evitar ser engañado por firewalls de clientes que bloquean *pings* aleatorios, el agente usa verificación en cascada:
- Intenta ping a Google (8.8.8.8), luego a Cloudflare (1.1.1.1), y finalmente una conexión HTTP encriptada. Solo si las tres fallan decreta una caída oficial.
- Paralelamente, mide la latencia de la respuesta en milisegundos. Si el internet funciona pero la velocidad supera los 500ms, el equipo se declara en estado **"Degradado"** para advertir de transacciones de pago lentas o fallidas.

---

## 🖥️ El Dashboard (Torre de Control Web)

La interfaz en tiempo real construida en React actúa como el punto central para el equipo directivo y de soporte:

- **Reactividad Instantánea (WebSocket):** Refleja si un equipo se apaga o sufre variaciones de latencia sin necesidad de recargar la página.
- **Exportación de Evidencia SLA:** Generador de reportes en formato `.csv` con 1 clic para auditar el "Uptime" o exigir compensaciones a los proveedores de internet del mall.
- **Glosario de Fallas Integrado:** Una "Wiki" de soporte directamente en la interfaz que traduce la compleja jerga de redes (ej: *Fallback, Gateway, IP*) a lenguaje humano, diciéndole al personal de soporte exactamente qué botón apretar, qué cable mirar o a quién llamar.
- **Filtrado Dinámico:** Permite visualizar rápidamente flotas específicas separadas por "Cliente" y "Sucursal".

> **Misión Cumplida:** Una herramienta de grado corporativo (*Enterprise*) que transforma un simple problema de "no hay internet" en métricas accionables y mantenimientos autónomos.
