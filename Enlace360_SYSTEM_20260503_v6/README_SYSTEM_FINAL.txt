ENLACE360 - KIT FINAL SYSTEM
Version kit: SYSTEM-2026-05-01.5

Objetivo:
Instalar el agente como NT AUTHORITY\SYSTEM sin payloads .dat, sin EncodedCommand,
sin validadores que reinstalan, y sin tareas PostBoot mutantes.

Copiar al PC cliente estos archivos:
- Agente_Enlace360_Service.ps1
- Instalar_Enlace360_SYSTEM.bat
- Instalar_Enlace360_SYSTEM.ps1
- Verificar_Enlace360_SYSTEM.bat
- Verificar_Enlace360_SYSTEM.ps1
- Diagnosticar_Enlace360_SYSTEM.bat
- Diagnosticar_Enlace360_SYSTEM.ps1

Instalacion:
1. Copiar esos archivos a una carpeta local, por ejemplo:
   C:\Users\ddigi\Downloads\Enlace360_SYSTEM
2. Ejecutar como Administrador:
   Instalar_Enlace360_SYSTEM.bat

Post-reinicio:
1. Reiniciar Windows.
2. Ejecutar como Administrador:
   Verificar_Enlace360_SYSTEM.bat
3. Enviar el log:
   C:\Enlace360_SYSTEM_verifier.log

Diagnostico de equipo offline/apagado:
1. Cuando el equipo vuelva a estar accesible, ejecutar como Administrador:
   Diagnosticar_Enlace360_SYSTEM.bat
2. Enviar el ZIP generado:
   C:\Enlace360_SYSTEM_Diagnostico_*.zip

Diagnostico si desaparecen las tareas:
1. No reinstalar todavia.
2. Ejecutar primero como Administrador:
   Diagnosticar_Enlace360_SYSTEM.bat
3. Revisar en el ZIP las secciones FORENSE TASKSCHEDULER, SECURITY,
   POWERSHELL, LOGONS REMOTOS, DEFENDER y REMOTE COMMANDS RECIENTES.
4. Despues de guardar el ZIP, reinstalar con:
   Instalar_Enlace360_SYSTEM.bat

Ruta instalada:
C:\ProgramData\Enlace360\Agent

Tareas esperadas:
- Enlace360_Agent
- Enlace360_HealthCheck

No usar para clientes:
- SUPER_*.ps1
- Instalar_Enlace360_Cliente.*
- Verificar_PostReinicio_Cliente.*
- Validar_Instalacion_Total.*
- Reparar_*.*
- Limpiador_Total.bat

Notas:
- Heartbeat queda en el agente principal.
- C2 vive dentro del agente principal; no depende de un poller auxiliar.
- HealthCheck corre al inicio y cada 5 minutos; relanza el agente si el proceso muere.
- agent_payload.cache es una copia local codificada del agente; HealthCheck y verificador la usan para restaurar Agente_Enlace360_Service.ps1 si Windows/EDR lo borra.
- El verificador no instala, no copia y no registra tareas.
- El verificador espera un heartbeat fresco antes de fallar, para evitar falsos FAIL cuando el equipo viene de muchas horas offline.
