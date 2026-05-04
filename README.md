# Enlace360 System Agent

Repositorio del dashboard y del agente Windows Enlace360 para monitoreo de kioscos.

## Version Operativa

- Kit: `SYSTEM-2026-05-01.5`
- Agente: `v3.6`
- Ruta Windows: `C:\ProgramData\Enlace360\Agent`
- Tareas Windows esperadas:
  - `Enlace360_Agent`
  - `Enlace360_HealthCheck`

El paquete cliente vigente esta en:

```text
Enlace360_SYSTEM_20260503_v6/
```

## Arquitectura Vigente

El agente principal `Agente_Enlace360_Service.ps1` corre como `NT AUTHORITY\SYSTEM` y contiene:

- heartbeat hacia Supabase
- C2 real via `remote_commands`
- reporte de eventos en `network_events`
- self-healing de red
- protocolo Lazaro con limite diario
- hot-swap por hash del propio archivo

`Enlace360_HealthCheck` se instala como tarea separada al inicio de Windows y cada 5 minutos. Su responsabilidad es restaurar el agente desde `agent_payload.cache`, recrear la tarea principal si falta y arrancar el proceso si muere.

## Instalacion En Cliente

Copiar al PC cliente el contenido completo de `Enlace360_SYSTEM_20260503_v6/` y ejecutar como Administrador:

```text
Instalar_Enlace360_SYSTEM.bat
```

El instalador solicita:

- cliente
- ubicacion/sucursal
- nombre del PC/kiosco

Luego registra las tareas SYSTEM, arranca el agente y ejecuta una verificacion rapida.

## Verificacion

Despues de instalar o reiniciar el PC cliente, ejecutar como Administrador:

```text
Verificar_Enlace360_SYSTEM.bat
```

El verificador comprueba:

- archivos instalados
- config local
- credenciales Supabase
- tareas SYSTEM
- proceso agente vivo
- heartbeat fresco
- avance del contador/heartbeat
- C2 roundtrip real
- recuperacion por HealthCheck
- cola `remote_commands` sin pendientes

Log principal:

```text
C:\Enlace360_SYSTEM_verifier.log
```

## Diagnostico

Para capturar evidencia local del cliente:

```text
Diagnosticar_Enlace360_SYSTEM.bat
```

Genera:

```text
C:\Enlace360_SYSTEM_Diagnostico_*.zip
```

Incluye tareas, procesos, logs, red, eventos de Windows, powercfg, estado local, fila Supabase y comandos pendientes.

Si las tareas `Enlace360_Agent` o `Enlace360_HealthCheck` desaparecen, no reinstalar primero. Ejecutar el diagnostico y guardar el ZIP antes de reparar. El diagnostico captura evidencia forense de Task Scheduler, Security Audit, PowerShell, sesiones remotas, Defender/EDR y comandos C2 recientes para distinguir borrado manual/remoto, politica/antivirus o falla de instalacion.

## Actualizacion Desde Dashboard

El dashboard envia un comando C2 que descarga:

```text
https://raw.githubusercontent.com/Enlace360/Monitoreo-de-red-/main/Agente_Enlace360_Service.ps1
```

Por eso el archivo raiz `Agente_Enlace360_Service.ps1` debe mantenerse identico al agente del kit SYSTEM vigente. El comando tambien actualiza `agent_payload.cache` para que HealthCheck no restaure una version antigua.

## No Usar En Clientes

La arquitectura anterior queda obsoleta:

- `C:\KioskNetMonitor`
- `Enlace360_Agent_Watchdog`
- `Enlace360_Agent_C2`
- `Enlace360_PostBoot_Validation`
- `Enlace360_C2_Poller.ps1`
- `Validar_Instalacion_Total.*`
- `Reparar_*`
- `Limpiador_Total.bat`
- payloads `.dat`
- `EncodedCommand`

## Checks Locales

```bash
node tests/agent_static_check.cjs
node tests/system_installer_static_check.cjs
node tests/dashboard_static_check.cjs
npm --prefix dashboard run build
```
