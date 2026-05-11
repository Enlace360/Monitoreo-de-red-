ENLACE360 - KIT SYSTEM
Version kit: SYSTEM-2026-05-10.1
Agente incluido: v3.8.1

Objetivo:
Instalar el agente en C:\ProgramData\Enlace360\Agent como servicio Windows
Enlace360Agent, con tareas SYSTEM solo como respaldo, cache local de recuperacion,
diagnostico forense e integridad visible en el dashboard.

Cambios v3.8.1:
- Hace deterministica la prueba de HealthCheck cuando el verificador dispara Enlace360_HealthCheck manualmente.
- Re-chequea el servicio Enlace360Agent antes de reportar warning de integridad por servicio detenido.

Cambios v3.8:
- Mantiene heartbeat, C2, self-healing de red, reporte de incidentes, hot-swap, Lazaro, logs rotativos y diagnostico local.
- Cambia heartbeat y C2 a RPC segura con AgentSecret local por equipo.
- Registra agent_secret_hash para proteger cada kiosco contra escrituras legacy.
- Agrega verificacion de integridad de servicio, tareas, archivos criticos y caches.
- Reporta integrity_status, integrity_alert, integrity_checked_at e integrity_details al dashboard.
- Mantiene el mismo modo de instalacion para el tecnico: ejecutar los .bat como Administrador.

Antes de instalar:
1. Ejecutar en Supabase el archivo supabase_schema.sql actualizado.
2. Verificar que el equipo tenga salida HTTPS a Supabase.
3. Configurar el secreto C2 Admin en Supabase antes de usar terminal remota:
   SELECT encode(digest('CAMBIA_ESTE_TOKEN_ADMIN', 'sha256'), 'hex');
   ALTER DATABASE postgres SET app.enlace360_admin_secret_sha256 = '<hash>';
   NOTIFY pgrst, 'reload config';
4. Para uso offline de USB, copiar tambien Enlace360Agent.exe junto al kit.
   Si no existe, el instalador descargara WinSW desde GitHub.

Copiar al PC cliente estos archivos:
- Agente_Enlace360_Service.ps1
- Instalar_Enlace360_SYSTEM.bat
- Instalar_Enlace360_SYSTEM.ps1
- Verificar_Enlace360_SYSTEM.bat
- Verificar_Enlace360_SYSTEM.ps1
- Diagnosticar_Enlace360_SYSTEM.bat
- Diagnosticar_Enlace360_SYSTEM.ps1
- AutoTest_Enlace360_SYSTEM.bat
- AutoTest_Enlace360_SYSTEM_Codex.bat
- AutoTest_Enlace360_SYSTEM.ps1

Flujo automatico recomendado para Codex Windows:
1. Copiar la carpeta completa del kit al PC Windows.
2. Ejecutar como Administrador:
   AutoTest_Enlace360_SYSTEM.bat
3. Elegir modo 1 para instalar, verificar y dejar programada la continuacion post-reinicio.
4. Si eliges reinicio automatico, el script reinicia Windows y continua solo al arrancar.
5. Revisar:
   C:\Enlace360_SYSTEM_autotest.log
   C:\Enlace360_SYSTEM_AutoTest_*.zip

Flujo sin prompts para Codex Windows:
1. Abrir PowerShell como Administrador en la carpeta del kit.
2. Ejecutar:
   .\AutoTest_Enlace360_SYSTEM_Codex.bat "Cenco Malls" "Costanera" "02 VTR - PB" AUTO_REBOOT
3. Para solo verificar un agente ya instalado:
   .\AutoTest_Enlace360_SYSTEM_Codex.bat "Cenco Malls" "Costanera" "02 VTR - PB" SKIP_INSTALL
4. Para continuar manualmente despues de reiniciar:
   .\AutoTest_Enlace360_SYSTEM_Codex.bat "Cenco Malls" "Costanera" "02 VTR - PB" POST_REBOOT

Instalacion limpia:
1. Copiar esos archivos a una carpeta local, por ejemplo:
   C:\Users\ddigi\Downloads\Enlace360_SYSTEM
2. Ejecutar como Administrador:
   Instalar_Enlace360_SYSTEM.bat
3. Esperar PASS del instalador.

Post-reinicio:
1. Reiniciar Windows.
2. Ejecutar como Administrador:
   Verificar_Enlace360_SYSTEM.bat
3. Confirmar que valida:
   - servicio Enlace360Agent running/automatic
   - tareas Enlace360_Agent y Enlace360_HealthCheck
   - heartbeat fresco en Supabase
   - C2 real ejecutado si ENLACE360_C2_ADMIN_SECRET esta definido
   - recuperacion por HealthCheck
   - restauracion si falta el archivo del agente
   - recreacion si falta la tarea principal
4. Enviar el log:
   C:\Enlace360_SYSTEM_verifier.log

Si El PC Ya Tiene Un Agente Anterior:
1. Si el PC esta funcionando normal y solo quieres actualizarlo, ejecutar directamente como Administrador:
   Instalar_Enlace360_SYSTEM.bat
2. El instalador nuevo hace limpieza controlada:
   - detiene el servicio anterior si existe
   - elimina Enlace360_Agent
   - elimina Enlace360_HealthCheck
   - elimina Enlace360_Agent_Watchdog
   - elimina Enlace360_Agent_C2
   - elimina Enlace360_PostBoot_Validation
   - detiene procesos PowerShell relacionados
   - instala todo de nuevo en C:\ProgramData\Enlace360\Agent
3. No usar reparadores antiguos ni scripts viejos para actualizar equipos sanos.

Si aparece ERROR 5 Acceso denegado:
1. Usar este kit SYSTEM-2026-05-10.1 o superior.
2. No borrar manualmente C:\ProgramData\Enlace360\Agent si necesitas preservar evidencia.
3. Si solo quieres recuperar el equipo, el instalador se encarga de resetear permisos con takeown/icacls antes de copiar.
4. Si el error persiste despues de reiniciar, ejecutar Diagnosticar_Enlace360_SYSTEM.bat y enviar el ZIP.

Ruta instalada:
C:\ProgramData\Enlace360\Agent

Servicio esperado:
- Enlace360Agent

Tareas esperadas:
- Enlace360_Agent
- Enlace360_HealthCheck

Archivos de recuperacion:
- agent_payload.cache
- healthcheck_payload.cache
- install_manifest.json
- integrity_state.json
- Enlace360Agent.xml

Campos nuevos del dashboard/Supabase:
- integrity_status
- integrity_alert
- integrity_checked_at
- integrity_details

Diagnostico si desaparecen tareas, servicio o archivos:
1. No reinstalar todavia.
2. Ejecutar primero como Administrador:
   Diagnosticar_Enlace360_SYSTEM.bat
3. Enviar el ZIP generado:
   C:\Enlace360_SYSTEM_Diagnostico_*.zip
4. Revisar en el ZIP:
   - FORENSE SERVICE CONTROL MANAGER ENLACE360
   - FORENSE TASKSCHEDULER OPERATIONAL ENLACE360
   - FORENSE SECURITY SCHEDULED TASKS
   - FORENSE POWERSHELL OPERATIONAL
   - FORENSE LOGONS REMOTOS
   - FORENSE TEAMVIEWER LOGS
   - FORENSE DEFENDER COMPLETO
   - FORENSE EVENT LOG CLEARS
   - SUPABASE REMOTE COMMANDS RECIENTES
5. Despues de guardar el ZIP, reinstalar con:
   Instalar_Enlace360_SYSTEM.bat

No usar para clientes:
- SUPER_*.ps1
- Instalar_Enlace360_Cliente.*
- Verificar_PostReinicio_Cliente.*
- Validar_Instalacion_Total.*
- Reparar_*.*
- Limpiador_Total.bat

Notas:
- La copia inicial del instalador usa logs detallados, staging temporal y recuperacion de ACL para evitar quedarse colgado sin diagnostico.
- Heartbeat vive dentro del agente principal.
- C2 vive dentro del agente principal; no depende de un poller auxiliar.
- El servicio Windows Enlace360Agent es el mecanismo principal de arranque.
- HealthCheck corre al inicio y cada 5 minutos como respaldo.
- HealthCheck permite disparos manuales del verificador aunque haya una instancia reciente en curso.
- Si falta Agente_Enlace360_Service.ps1, HealthCheck lo restaura desde agent_payload.cache.
- Si falta la tarea principal, HealthCheck la recrea como SYSTEM.
- Si faltan archivos, tareas o servicio, el agente reporta integrity_status/integrity_alert al dashboard.
