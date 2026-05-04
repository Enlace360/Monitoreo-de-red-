const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const kit = path.join(root, 'Enlace360_SYSTEM_20260503_v6');

function read(name) {
  return fs.readFileSync(path.join(kit, name), 'utf8');
}

function assertIncludes(source, expected, label) {
  assert(source.includes(expected), `${label} must include: ${expected}`);
}

function assertNotIncludes(source, unexpected, label) {
  assert(!source.includes(unexpected), `${label} must not include: ${unexpected}`);
}

const expectedFiles = [
  'Agente_Enlace360_Service.ps1',
  'Instalar_Enlace360_SYSTEM.bat',
  'Instalar_Enlace360_SYSTEM.ps1',
  'Verificar_Enlace360_SYSTEM.bat',
  'Verificar_Enlace360_SYSTEM.ps1',
  'Diagnosticar_Enlace360_SYSTEM.bat',
  'Diagnosticar_Enlace360_SYSTEM.ps1',
  'README_SYSTEM_FINAL.txt',
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
const readme = read('README_SYSTEM_FINAL.txt');

assertIncludes(readme, 'Version kit: SYSTEM-2026-05-01.5', 'readme version');
assertIncludes(readme, 'C:\\ProgramData\\Enlace360\\Agent', 'readme install path');
assertIncludes(readme, 'Enlace360_Agent', 'readme agent task');
assertIncludes(readme, 'Enlace360_HealthCheck', 'readme health task');
assertIncludes(readme, 'C2 vive dentro del agente principal', 'readme c2 architecture');
assertIncludes(readme, 'agent_payload.cache', 'readme cache restore');

assertIncludes(installerBat, 'Verb RunAs', 'installer wrapper admin elevation');
assertIncludes(installerBat, 'set "INSTALL_DIR=C:\\ProgramData\\Enlace360\\Agent"', 'installer wrapper install path');
assertIncludes(installerBat, 'set /p "CLIENT_NAME=', 'installer wrapper prompts client');
assertIncludes(installerBat, '-ClientName "%CLIENT_NAME%" -Location "%LOCATION%" -KioskName "%KIOSK_NAME%"', 'installer wrapper passes config');

assertIncludes(installer, '$InstallerVersion = "SYSTEM-2026-05-01.5"', 'installer version');
assertIncludes(installer, '[string]$InstallDir = "C:\\ProgramData\\Enlace360\\Agent"', 'installer default path');
assertIncludes(installer, '$TaskAgent = "Enlace360_Agent"', 'installer agent task');
assertIncludes(installer, '$TaskHealthCheck = "Enlace360_HealthCheck"', 'installer health task');
assertIncludes(installer, '$TaskLegacyWatchdog = "Enlace360_Agent_Watchdog"', 'installer removes legacy watchdog');
assertIncludes(installer, '$TaskLegacyC2 = "Enlace360_Agent_C2"', 'installer removes legacy c2');
assertIncludes(installer, '$TaskLegacyPostBoot = "Enlace360_PostBoot_Validation"', 'installer removes legacy postboot');
assertIncludes(installer, 'agent_payload.cache', 'installer creates cache');
assertIncludes(installer, '[Convert]::ToBase64String([System.IO.File]::ReadAllBytes($AgentSource))', 'installer caches agent bytes');
assertIncludes(installer, 'Restore-AgentFromCache', 'healthcheck restores missing agent');
assertIncludes(installer, 'Register-ScheduledTask -TaskName $TaskAgent', 'installer registers agent task');
assertIncludes(installer, 'Register-ScheduledTask -TaskName $TaskHealthCheck', 'installer registers healthcheck task');
assertIncludes(installer, 'New-ScheduledTaskPrincipal -UserId "SYSTEM"', 'installer runs as SYSTEM');
assertIncludes(installer, 'New-ScheduledTaskTrigger -AtStartup', 'installer startup trigger');
assertIncludes(installer, 'New-ScheduledTaskTrigger -AtLogOn', 'installer logon trigger');
assertIncludes(installer, 'RepetitionInterval (New-TimeSpan -Minutes 5)', 'installer healthcheck repeats every five minutes');
assertIncludes(installer, 'install_manifest.json', 'installer writes manifest');
assertIncludes(installer, '& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $VerifierPath', 'installer runs quick verifier');
assertNotIncludes(installer, '-EncodedCommand', 'installer encoded commands');
assertNotIncludes(installer, 'Enlace360_C2_Poller.ps1', 'installer external c2 poller');

assertIncludes(verifierBat, 'Verb RunAs', 'verifier wrapper admin elevation');
assertIncludes(verifierBat, '-ObserveSeconds %OBSERVE_SECONDS% -TestHealthCheck', 'verifier wrapper tests healthcheck');
assertIncludes(verifier, '$VerifierVersion = "SYSTEM-2026-05-01.5"', 'verifier version');
assertIncludes(verifier, 'Restore-AgentFromCache', 'verifier restores missing agent');
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
assertIncludes(diag, '$DiagnosticVersion = "SYSTEM-DIAG-2026-05-04.1"', 'diagnostic version');
assertIncludes(diag, 'Compress-Archive', 'diagnostic creates zip');
assertIncludes(diag, 'SUPABASE KIOSK ROW', 'diagnostic captures kiosk row');
assertIncludes(diag, 'SUPABASE REMOTE COMMANDS PENDING', 'diagnostic captures pending commands');
assertIncludes(diag, 'SUPABASE REMOTE COMMANDS RECIENTES', 'diagnostic captures recent commands');
assertIncludes(diag, 'FORENSE TASKSCHEDULER OPERATIONAL ENLACE360', 'diagnostic captures task scheduler history');
assertIncludes(diag, 'FORENSE SECURITY SCHEDULED TASKS', 'diagnostic captures security task events');
assertIncludes(diag, 'FORENSE SECURITY PROCESS CREATION', 'diagnostic captures process creation audit');
assertIncludes(diag, 'FORENSE POWERSHELL OPERATIONAL', 'diagnostic captures PowerShell operational logs');
assertIncludes(diag, 'FORENSE LOGONS REMOTOS', 'diagnostic captures remote logon evidence');
assertIncludes(diag, 'FORENSE HERRAMIENTAS REMOTAS', 'diagnostic captures remote access tools');
assertIncludes(diag, 'FORENSE DEFENDER ENLACE360', 'diagnostic captures Defender evidence');
assertIncludes(diag, 'FORENSE AUDIT POLICY', 'diagnostic captures audit policy');
assertIncludes(diag, 'powercfg.exe', 'diagnostic captures power state');
assertIncludes(diag, 'Get-WinEvent', 'diagnostic captures Windows events');
assertIncludes(diag, 'C:\\Enlace360_SYSTEM_Diagnostico_', 'diagnostic output zip prefix');

assertIncludes(agent, 'Function Check-RemoteCommands', 'agent integrated c2');
assertNotIncludes(agent, 'Enlace360_C2_Poller.ps1', 'agent external c2 poller');

for (const [label, source] of Object.entries({ installer, verifier, diag, agent })) {
  assertNotIncludes(source, 'SUPER_', `${label} legacy super scripts`);
  assertNotIncludes(source, 'Validar_Instalacion_Total', `${label} legacy validator`);
  assertNotIncludes(source, 'Reparar_Arranque', `${label} legacy repair`);
  assertNotIncludes(source, 'C:\\KioskNetMonitor', `${label} legacy kiosk path`);
}

console.log('SYSTEM installer static checks passed.');
