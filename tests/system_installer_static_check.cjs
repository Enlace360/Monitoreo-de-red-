const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const kit = path.join(root, 'usb-kit-2026-05-09');

function read(name) {
  return fs.readFileSync(path.join(kit, name), 'utf8');
}

function assertIncludes(source, expected, label) {
  assert(source.includes(expected), `${label} must include: ${expected}`);
}

function assertNotIncludes(source, unexpected, label) {
  assert(!source.includes(unexpected), `${label} must not include: ${unexpected}`);
}

function assertMatches(source, expected, label) {
  assert(expected.test(source), `${label} must match: ${expected}`);
}

const expectedFiles = [
  'Agente_Enlace360_Service.ps1',
  'Instalar_Enlace360_SYSTEM.bat',
  'Instalar_Enlace360_SYSTEM.ps1',
  'Verificar_Enlace360_SYSTEM.bat',
  'Verificar_Enlace360_SYSTEM.ps1',
  'Diagnosticar_Enlace360_SYSTEM.bat',
  'Diagnosticar_Enlace360_SYSTEM.ps1',
  'AutoTest_Enlace360_SYSTEM.bat',
  'AutoTest_Enlace360_SYSTEM_Codex.bat',
  'AutoTest_Enlace360_SYSTEM.ps1',
  'CHECKSUMS_SHA256.txt',
  'README_SYSTEM_FINAL.txt',
  'supabase_schema.sql',
];

for (const file of expectedFiles) {
  assert(fs.existsSync(path.join(kit, file)), `kit must include ${file}`);
}

const agent = read('Agente_Enlace360_Service.ps1');
const installerBat = read('Instalar_Enlace360_SYSTEM.bat');
const installer = read('Instalar_Enlace360_SYSTEM.ps1');
const verifierBat = read('Verificar_Enlace360_SYSTEM.bat');
const verifier = read('Verificar_Enlace360_SYSTEM.ps1');
const diagBat = read('Diagnosticar_Enlace360_SYSTEM.bat');
const diag = read('Diagnosticar_Enlace360_SYSTEM.ps1');
const autoTestBat = read('AutoTest_Enlace360_SYSTEM.bat');
const autoTestCodexBat = read('AutoTest_Enlace360_SYSTEM_Codex.bat');
const autoTest = read('AutoTest_Enlace360_SYSTEM.ps1');
const readme = read('README_SYSTEM_FINAL.txt');

const checksumLines = read('CHECKSUMS_SHA256.txt')
  .trim()
  .split(/\r?\n/)
  .filter(Boolean);
for (const line of checksumLines) {
  const match = /^([a-f0-9]{64})\s{2}(.+)$/.exec(line);
  assert(match, `checksum line must be '<sha256>  <file>': ${line}`);
  const [, expectedHash, fileName] = match;
  const filePath = path.join(kit, fileName);
  assert(fs.existsSync(filePath), `checksum target must exist: ${fileName}`);
  const actualHash = crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex');
  assert.strictEqual(actualHash, expectedHash, `checksum mismatch for ${fileName}`);
}

assertIncludes(readme, 'Version kit: SYSTEM-2026-06-04.1', 'readme version');
assertIncludes(readme, 'Agente incluido: v3.8.2', 'readme agent version');
assertIncludes(readme, 'C:\\ProgramData\\Enlace360\\Agent', 'readme install path');
assertIncludes(readme, 'Enlace360_Agent', 'readme agent task');
assertIncludes(readme, 'Enlace360_HealthCheck', 'readme health task');
assertIncludes(readme, 'C2 vive dentro del agente principal', 'readme c2 architecture');
assertIncludes(readme, 'agent_payload.cache', 'readme cache restore');
assertIncludes(readme, 'Enlace360Agent', 'readme service name');
assertIncludes(readme, 'integrity_status', 'readme integrity fields');
assertIncludes(readme, 'Si El PC Ya Tiene Un Agente Anterior', 'readme existing-agent path');
assertIncludes(readme, 'detiene el servicio anterior si existe', 'readme existing service cleanup');
assertIncludes(readme, 'elimina Enlace360_Agent_Watchdog', 'readme legacy watchdog cleanup');
assertIncludes(readme, 'restauracion si falta el archivo del agente', 'readme verifier agent restore check');
assertIncludes(readme, 'recreacion si falta la tarea principal', 'readme verifier task recreation check');
assertIncludes(readme, 'No reinstalar todavia', 'readme preserves forensic evidence before reinstall');
assertIncludes(readme, 'ERROR 5 Acceso denegado', 'readme documents access denied path');
assertIncludes(readme, 'resetear permisos', 'readme explains permission reset');
assertIncludes(readme, 'Flujo automatico recomendado para Codex Windows', 'readme documents guided autotest flow');
assertIncludes(readme, 'Flujo sin prompts para Codex Windows', 'readme documents noninteractive codex flow');
assertIncludes(readme, 'AutoTest_Enlace360_SYSTEM_Codex.bat "Cenco Malls" "Costanera" "02 VTR - PB" AUTO_REBOOT', 'readme documents one-line codex autotest');

assertIncludes(installerBat, 'Verb RunAs', 'installer wrapper admin elevation');
assertIncludes(installerBat, 'set "INSTALL_DIR=C:\\ProgramData\\Enlace360\\Agent"', 'installer wrapper install path');
assertIncludes(installerBat, 'set /p "CLIENT_NAME=', 'installer wrapper prompts client');
assertIncludes(installerBat, '-ClientName "%CLIENT_NAME%" -Location "%LOCATION%" -KioskName "%KIOSK_NAME%"', 'installer wrapper passes config');

assertIncludes(installer, '$InstallerVersion = "SYSTEM-2026-06-04.1"', 'installer version');
assertIncludes(installer, '[string]$AgentSecret = ""', 'installer accepts optional agent secret');
assertIncludes(installer, 'function New-AgentSecret', 'installer generates agent secret');
assertIncludes(installer, 'AgentSecret = $AgentSecret', 'installer writes agent secret to config');
assertIncludes(installer, '("Servicio {0}: Status={1}; StartType={2}" -f $ServiceName, $svc.Status, $svc.StartType)', 'installer safe service state log interpolation');
assertIncludes(installer, '("Servicio {0}: NO EXISTE" -f $ServiceName)', 'installer safe missing service log interpolation');
assertIncludes(installer, '("Tarea {0}: State={1}; User={2}; Last={3}" -f $taskName, $task.State, $task.Principal.UserId, $info.LastTaskResult)', 'installer safe task state log interpolation');
assertIncludes(installer, '("Tarea {0}: NO EXISTE" -f $taskName)', 'installer safe missing task log interpolation');
assertIncludes(installer, '("[WARN] No se pudo leer ACL de {0}: {1}" -f $Path, $_.Exception.Message)', 'installer safe ACL warning interpolation');
assertIncludes(installer, '("[ERROR] No se pudo asegurar servicio {0}: {1}" -f $ServiceName, $_.Exception.Message)', 'embedded healthcheck safe service error interpolation');
assertNotIncludes(installer, '$ServiceName:', 'installer unsafe ServiceName colon interpolation');
assertNotIncludes(installer, '$taskName:', 'installer unsafe taskName colon interpolation');
assertNotIncludes(installer, '$Path`:', 'installer unsafe escaped Path colon interpolation');
const unsafeColonInterpolations = (installer.match(/\$[A-Za-z_][A-Za-z0-9_]*:/g) || [])
  .filter((match) => !['$env:', '$script:', '$global:', '$local:', '$private:', '$using:'].includes(match));
assert.deepStrictEqual(unsafeColonInterpolations, [], `installer has unsafe PowerShell colon interpolation: ${unsafeColonInterpolations.join(', ')}`);
assertIncludes(installer, 'Copy-KitFile', 'installer uses logged bounded file copy');
assertIncludes(installer, 'OK copia $Label hash=$hash', 'installer logs copied file hash');
assertIncludes(installer, 'Write-InstallStateSnapshot', 'installer logs service task process state');
assertIncludes(installer, 'Repair-InstallDirectoryPermissions', 'installer repairs install directory permissions');
assertIncludes(installer, 'takeown.exe', 'installer takes ownership before copying');
assertIncludes(installer, 'icacls.exe $InstallDir /reset', 'installer resets ACL before copying');
assertIncludes(installer, 'ACL ANTES DE REPARAR PERMISOS', 'installer logs ACL before repair');
assertIncludes(installer, 'ACL DESPUES DE REPARAR PERMISOS', 'installer logs ACL after repair');
assertIncludes(installer, '$StagingRoot', 'installer uses staging copy root');
assertIncludes(installer, 'Copy-KitFileToStaging', 'installer copies source to staging first');
assertIncludes(installer, 'Write-CopyFailureDiagnostics', 'installer writes copy failure diagnostics');
assertIncludes(installer, 'Reinicia Windows y ejecuta Diagnosticar_Enlace360_SYSTEM.bat', 'installer logs operational recommendation on persistent lock');
assertIncludes(installer, '[string]$InstallDir = "C:\\ProgramData\\Enlace360\\Agent"', 'installer default path');
assertIncludes(installer, '$TaskAgent = "Enlace360_Agent"', 'installer agent task');
assertIncludes(installer, '$TaskHealthCheck = "Enlace360_HealthCheck"', 'installer health task');
assertIncludes(installer, '$ServiceName = "Enlace360Agent"', 'installer service name');
assertIncludes(installer, '$WinSWDownloadUrl = "https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe"', 'installer WinSW official download URL');
assertIncludes(installer, 'Write-ServiceWrapperConfig', 'installer writes WinSW XML');
assertIncludes(installer, 'Install-AgentService', 'installer installs service wrapper');
assertIncludes(installer, 'sc.exe failure $ServiceName', 'installer configures SCM recovery');
assertIncludes(installer, '$TaskLegacyWatchdog = "Enlace360_Agent_Watchdog"', 'installer removes legacy watchdog');
assertIncludes(installer, '$TaskLegacyC2 = "Enlace360_Agent_C2"', 'installer removes legacy c2');
assertIncludes(installer, '$TaskLegacyPostBoot = "Enlace360_PostBoot_Validation"', 'installer removes legacy postboot');
assertIncludes(installer, 'agent_payload.cache', 'installer creates cache');
assertIncludes(installer, 'healthcheck_payload.cache', 'installer creates healthcheck cache');
assertIncludes(installer, '[Convert]::ToBase64String([System.IO.File]::ReadAllBytes($AgentSource))', 'installer caches agent bytes');
assertIncludes(installer, 'Restore-AgentFromCache', 'healthcheck restores missing agent');
assertIncludes(installer, 'Restore-HealthCheckFromCache', 'healthcheck restores itself from cache');
assertIncludes(installer, 'Ensure-AgentService', 'healthcheck ensures service');
assertIncludes(installer, 'Register-ScheduledTask -TaskName $TaskAgent', 'installer registers agent task');
assertIncludes(installer, 'Register-ScheduledTask -TaskName $TaskHealthCheck', 'installer registers healthcheck task');
assertIncludes(installer, 'New-ScheduledTaskPrincipal -UserId "SYSTEM"', 'installer runs as SYSTEM');
assertIncludes(installer, 'triggers = @("ManualFallback")', 'installer documents agent task as manual fallback');
assertIncludes(installer, 'New-ScheduledTaskTrigger -AtStartup', 'installer healthcheck/postreboot startup trigger');
assertNotIncludes(installer, 'New-ScheduledTaskTrigger -AtLogOn', 'agent task must not auto-start at logon');
assertNotIncludes(installer, 'triggers = @("AtStartup", "AtLogOn")', 'agent manifest must not describe automatic triggers');
assertIncludes(installer, 'RepetitionInterval (New-TimeSpan -Minutes 5)', 'installer healthcheck repeats every five minutes');
assertMatches(installer, /\$agentSettings = New-ScheduledTaskSettingsSet[\s\S]*?-MultipleInstances IgnoreNew[\s\S]*?Register-ScheduledTask -TaskName \$TaskAgent -Action \$agentAction -Principal/, 'agent task is manual fallback without automatic triggers');
assertMatches(installer, /\$healthSettings = New-ScheduledTaskSettingsSet[\s\S]*?-MultipleInstances Parallel[\s\S]*?Register-ScheduledTask -TaskName \$TaskHealthCheck/, 'healthcheck task allows deterministic verifier trigger');
assertMatches(installer, /function Ensure-AgentTask[\s\S]*?New-ScheduledTaskSettingsSet[\s\S]*?-MultipleInstances IgnoreNew[\s\S]*?Register-ScheduledTask -TaskName \$TaskName -Action \(New-SystemPowerShellActionLocal \$AgentPath\) -Principal/, 'healthcheck restores manual fallback agent task with duplicate protection');
assertIncludes(installer, 'install_manifest.json', 'installer writes manifest');
assertIncludes(installer, '& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $VerifierPath', 'installer runs quick verifier');
assertNotIncludes(installer, '-EncodedCommand', 'installer encoded commands');
assertNotIncludes(installer, 'Enlace360_C2_Poller.ps1', 'installer external c2 poller');

assertIncludes(verifierBat, 'Verb RunAs', 'verifier wrapper admin elevation');
assertIncludes(verifierBat, '-ObserveSeconds %OBSERVE_SECONDS% -TestHealthCheck', 'verifier wrapper tests healthcheck');
assertIncludes(verifier, '$VerifierVersion = "SYSTEM-2026-06-04.1"', 'verifier version');
assertIncludes(verifier, 'Enlace360Agent', 'verifier checks service');
assertIncludes(verifier, 'integrity_status', 'verifier reads integrity fields');
assertIncludes(verifier, 'ENLACE360_C2_ADMIN_SECRET', 'verifier reads C2 admin secret from env');
assertIncludes(verifier, '/rest/v1/rpc/enlace360_enqueue_remote_command', 'verifier enqueues C2 through RPC');
assertIncludes(verifier, '/rest/v1/rpc/enlace360_list_remote_commands', 'verifier reads C2 through RPC');
assertIncludes(verifier, 'Restore-AgentFromCache', 'verifier restores missing agent');
assertIncludes(verifier, 'function Start-HealthCheckDeterministic', 'verifier has deterministic healthcheck trigger');
assertIncludes(verifier, 'Assert-NoFalseServiceIntegrityWarning', 'verifier checks false service integrity warning');
assert((verifier.match(/Start-HealthCheckDeterministic/g) || []).length >= 4, 'verifier must use deterministic healthcheck trigger in all healthcheck checks');
assertIncludes(verifier, 'Wait-FreshHeartbeat', 'verifier waits fresh heartbeat');
assertIncludes(verifier, 'Wait-HeartbeatAdvance', 'verifier checks dashboard counter');
assertIncludes(verifier, 'Test-C2Roundtrip', 'verifier tests real c2');
assertIncludes(verifier, 'HealthCheck recupera proceso muerto', 'verifier tests healthcheck recovery');
assertIncludes(verifier, 'Pending remote_commands vacio', 'verifier checks pending queue');
assertIncludes(verifier, 'PASS VERIFICACION SYSTEM ENLACE360', 'verifier pass marker');
assertNotIncludes(verifier, 'Register-ScheduledTask', 'verifier must not install tasks');
assertNotIncludes(verifier, 'Copy-Item', 'verifier must not copy kit files');
assertNotIncludes(verifier, '-EncodedCommand', 'verifier encoded commands');

assertIncludes(diagBat, 'Verb RunAs', 'diagnostic wrapper admin elevation');
assertIncludes(diagBat, '-RunVerifier', 'diagnostic can run verifier');
assertIncludes(diag, '$DiagnosticVersion = "SYSTEM-DIAG-2026-05-06.1"', 'diagnostic version');
assertIncludes(diag, 'Compress-Archive', 'diagnostic creates zip');
assertIncludes(diag, 'Read-SupabaseCredentials', 'diagnostic reads Supabase credentials resiliently');
assertIncludes(diag, 'agent_payload.cache', 'diagnostic reads credentials from cache if agent file is missing');
assertIncludes(diag, 'SUPABASE KIOSK ROW', 'diagnostic captures kiosk row');
assertIncludes(diag, 'SUPABASE REMOTE COMMANDS PENDING', 'diagnostic captures pending commands');
assertIncludes(diag, 'SUPABASE REMOTE COMMANDS RECIENTES', 'diagnostic captures recent commands');
assertIncludes(diag, 'ENLACE360_C2_ADMIN_SECRET', 'diagnostic reads C2 admin secret from env');
assertIncludes(diag, '/rest/v1/rpc/enlace360_list_remote_commands', 'diagnostic reads C2 through RPC');
assertNotIncludes(diag, '/rest/v1/remote_commands?kiosk_id=eq.', 'diagnostic direct remote_commands table read');
assertIncludes(diag, 'FORENSE TASKSCHEDULER OPERATIONAL ENLACE360', 'diagnostic captures task scheduler history');
assertIncludes(diag, 'FORENSE SECURITY SCHEDULED TASKS', 'diagnostic captures security task events');
assertIncludes(diag, 'FORENSE SECURITY PROCESS CREATION', 'diagnostic captures process creation audit');
assertIncludes(diag, 'FORENSE POWERSHELL OPERATIONAL', 'diagnostic captures PowerShell operational logs');
assertIncludes(diag, 'FORENSE LOGONS REMOTOS', 'diagnostic captures remote logon evidence');
assertIncludes(diag, 'FORENSE HERRAMIENTAS REMOTAS', 'diagnostic captures remote access tools');
assertIncludes(diag, 'FORENSE TEAMVIEWER LOGS', 'diagnostic captures TeamViewer logs');
assertIncludes(diag, 'FORENSE DEFENDER ENLACE360', 'diagnostic captures Defender evidence');
assertIncludes(diag, 'FORENSE DEFENDER COMPLETO', 'diagnostic captures full Defender evidence');
assertIncludes(diag, 'FORENSE SERVICE CONTROL MANAGER ENLACE360', 'diagnostic captures service install/start evidence');
assertIncludes(diag, 'FORENSE EVENT LOG CLEARS', 'diagnostic captures event log clearing evidence');
assertIncludes(diag, 'FORENSE INSTALACION/DESINSTALACION', 'diagnostic captures install/uninstall events');
assertIncludes(diag, 'FORENSE SCRIPTS SOSPECHOSOS LOCALES', 'diagnostic captures cleaner/repair scripts');
assertIncludes(diag, 'FORENSE AUDIT POLICY', 'diagnostic captures audit policy');
assertIncludes(diag, '"/get", "/subcategory:$subcategory"', 'diagnostic quotes auditpol subcategories with spaces');
assertIncludes(diag, 'powercfg.exe', 'diagnostic captures power state');
assertIncludes(diag, 'Get-WinEvent', 'diagnostic captures Windows events');
assertIncludes(diag, 'C:\\Enlace360_SYSTEM_Diagnostico_', 'diagnostic output zip prefix');

assertIncludes(autoTestBat, 'Verb RunAs', 'autotest wrapper admin elevation');
assertIncludes(autoTestBat, 'AutoTest_Enlace360_SYSTEM.ps1', 'autotest wrapper calls ps1');
assertIncludes(autoTestBat, '-ClientName "%CLIENT_NAME%" -Location "%LOCATION%" -KioskName "%KIOSK_NAME%"', 'autotest wrapper passes config');
assertIncludes(autoTestBat, '-AutoReboot', 'autotest wrapper supports automatic reboot');
assertIncludes(autoTestBat, '-SkipInstall', 'autotest wrapper supports verifier-only mode');
assertIncludes(autoTestBat, 'C:\\Enlace360_SYSTEM_autotest.log', 'autotest wrapper documents log');
assertIncludes(autoTestCodexBat, 'AutoTest_Enlace360_SYSTEM.ps1', 'autotest codex wrapper calls ps1');
assertIncludes(autoTestCodexBat, 'set "CLIENT_NAME=%~1"', 'autotest codex wrapper accepts client arg');
assertIncludes(autoTestCodexBat, 'set "LOCATION=%~2"', 'autotest codex wrapper accepts location arg');
assertIncludes(autoTestCodexBat, 'set "KIOSK_NAME=%~3"', 'autotest codex wrapper accepts kiosk arg');
assertIncludes(autoTestCodexBat, 'AUTO_REBOOT', 'autotest codex wrapper supports automatic reboot flag');
assertIncludes(autoTestCodexBat, 'SKIP_INSTALL', 'autotest codex wrapper supports skip install flag');
assertIncludes(autoTestCodexBat, 'POST_REBOOT', 'autotest codex wrapper supports post reboot flag');
assertIncludes(autoTestCodexBat, '-ClientName "%CLIENT_NAME%" -Location "%LOCATION%" -KioskName "%KIOSK_NAME%"', 'autotest codex wrapper passes config');
assertIncludes(autoTest, '$AutoTestVersion = "SYSTEM-2026-06-04.1"', 'autotest version');
assertIncludes(autoTest, 'Assert-PowerShellSyntax', 'autotest parses scripts before execution');
assertIncludes(autoTest, '[System.Management.Automation.Language.Parser]::ParseFile', 'autotest uses parser API');
assertIncludes(autoTest, 'Invoke-Installer', 'autotest invokes installer directly');
assertIncludes(autoTest, 'Invoke-Verifier', 'autotest invokes verifier directly');
assertIncludes(autoTest, 'Register-PostRebootTask', 'autotest schedules post reboot continuation');
assertIncludes(autoTest, 'Enlace360_SYSTEM_AutoTest_PostReboot', 'autotest task name');
assertIncludes(autoTest, 'Export-AutoTestEvidence', 'autotest exports evidence zip');
assertIncludes(autoTest, 'C:\\Enlace360_SYSTEM_AutoTest_', 'autotest evidence zip prefix');
assertIncludes(autoTest, 'Get-Service -Name $ServiceName', 'autotest checks service');
assertIncludes(autoTest, 'Get-ScheduledTask -TaskName', 'autotest checks tasks');
assertIncludes(autoTest, 'remote_commands', 'autotest preserves c2 verification context');
assertNotIncludes(autoTest, '-EncodedCommand', 'autotest encoded commands');

assertIncludes(agent, 'Function Check-RemoteCommands', 'agent integrated c2');
assertIncludes(agent, 'Function Get-AgentIntegrity', 'agent reports integrity');
assertIncludes(agent, '$AgentVersion = "v3.8.2"', 'agent version');
assertIncludes(agent, 'Switch-ToServicePrimaryIfNeeded', 'agent hands off old task-triggered launches to service');
assertIncludes(agent, 'Confirm-ServiceRunningStable', 'agent rechecks service before integrity warning');
assertIncludes(agent, '/rest/v1/rpc/enlace360_claim_remote_commands', 'agent claims c2 via rpc');
assertIncludes(agent, '/rest/v1/rpc/enlace360_complete_remote_command', 'agent completes c2 via rpc');
assertNotIncludes(agent, '/rest/v1/remote_commands', 'agent direct remote command table access');
assertNotIncludes(verifier, '/rest/v1/remote_commands', 'verifier direct remote command table access');
assertNotIncludes(agent, 'Enlace360_C2_Poller.ps1', 'agent external c2 poller');

for (const [label, source] of Object.entries({ installer, verifier, diag, agent })) {
  assertNotIncludes(source, 'SUPER_', `${label} legacy super scripts`);
  assertNotIncludes(source, 'Validar_Instalacion_Total', `${label} legacy validator`);
  assertNotIncludes(source, 'Reparar_Arranque', `${label} legacy repair`);
  assertNotIncludes(source, 'C:\\KioskNetMonitor', `${label} legacy kiosk path`);
}

console.log('SYSTEM installer static checks passed.');
