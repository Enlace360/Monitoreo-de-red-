const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'dashboard', 'src', 'App.jsx'), 'utf8');
const css = fs.readFileSync(path.join(root, 'dashboard', 'src', 'index.css'), 'utf8');
const supabaseClient = fs.readFileSync(path.join(root, 'dashboard', 'src', 'supabaseClient.js'), 'utf8');

function includes(expected, label = expected) {
  assert(app.includes(expected), `dashboard must include: ${label}`);
}

function notIncludes(unexpected, label = unexpected) {
  assert(!app.includes(unexpected), `dashboard must not include: ${label}`);
}

includes('const AGENT_UPDATE_COMMAND =', 'shared update command constant');
includes('HEARTBEAT_OFFLINE_THRESHOLD_MINUTES', 'dashboard centralizes heartbeat offline threshold');
includes('getHeartbeatAgeMinutes', 'dashboard computes heartbeat age');
includes('heartbeat_label', 'dashboard exposes heartbeat age label');
includes('heartbeat_stale', 'dashboard tracks stale heartbeats');
includes('data-banner warning', 'dashboard warns when most heartbeats are stale');
includes('kiosk-heartbeat', 'dashboard displays heartbeat age per kiosk');
includes('terminalKioskInfo', 'dashboard derives terminal kiosk details from current data');
includes('terminal-device-meta', 'terminal modal displays device network identifiers');
includes('terminalKioskInfo?.ip_address', 'terminal modal shows kiosk IP');
includes('terminalKioskInfo?.mac_address', 'terminal modal shows kiosk MAC');
includes('getIntegrityInfo', 'dashboard computes integrity display state');
includes('getAgentVersion', 'dashboard parses agent version from uptime');
includes('isIntegrityCapableVersion', 'dashboard distinguishes legacy agents from v3.8 integrity-capable agents');
includes('Pendiente v3.8', 'dashboard labels legacy agents as pending v3.8 instead of failed integrity');
includes('Integridad pendiente', 'dashboard labels v3.8 unknown integrity separately');
includes('integrity_status', 'dashboard reads integrity status');
includes('integrity_alert', 'dashboard reads integrity alert');
includes('integrityCount', 'dashboard counts integrity alerts');
includes('Integridad', 'dashboard has integrity stat');
includes('integrity-pill', 'dashboard shows card-level integrity badge');
includes('kiosk-card integrity-', 'dashboard applies integrity card class');
assert(css.includes('.integrity-pill.legacy'), 'dashboard styles legacy integrity status neutrally');
assert(css.includes('.terminal-device-meta'), 'dashboard styles terminal network metadata');
includes('C:\\\\ProgramData\\\\Enlace360\\\\Agent', 'SYSTEM install path in update command');
includes('agent_payload.cache', 'cache update in dashboard command');
includes('[Convert]::ToBase64String([System.IO.File]::ReadAllBytes($agent))', 'dashboard refreshes cache after agent download');
includes('raw.githubusercontent.com/Enlace360/Monitoreo-de-red-/main/Agente_Enlace360_Service.ps1', 'root raw agent update URL');
includes('sendCommand(AGENT_UPDATE_COMMAND)', 'single-kiosk update uses shared command');
includes('p_command_string: AGENT_UPDATE_COMMAND', 'bulk update uses shared command through RPC');
includes('const targetKiosks = filteredKiosks', 'bulk update uses visible filtered kiosks');
includes('targetKiosks.length === 0', 'bulk update handles empty list');
includes("supabase.rpc('enlace360_enqueue_remote_command'", 'dashboard enqueues commands through secure RPC');
includes("supabase.rpc('enlace360_list_remote_commands'", 'dashboard reads command history through secure RPC');
includes('c2AdminSecret', 'dashboard requires C2 admin secret');
includes('sessionStorage.setItem', 'C2 admin secret is not bundled into the build');
notIncludes(".from('remote_commands')", 'direct remote_commands table access from dashboard');
notIncludes('C:\\\\KioskNetMonitor\\\\Agente_Enlace360_Service.ps1', 'legacy update path');
notIncludes('kiosks.length', 'undefined kiosks variable');
notIncludes('for (const kiosk of kiosks)', 'undefined kiosks loop');
notIncludes('<span>IP: {kiosk.ip_address', 'kiosk cards must not show IP');
notIncludes('<span>MAC: {kiosk.mac_address', 'kiosk cards must not show MAC');
notIncludes('Mall La Reina', 'dashboard must not synthesize demo malls');
notIncludes('TOTEM-', 'dashboard must not synthesize demo kiosk ids');
notIncludes('Math.random()', 'dashboard must not synthesize random demo telemetry');

assert(supabaseClient.includes('https://zhvykvpixpkjegfxgwer.supabase.co'), 'dashboard must default to current Supabase project');
assert(supabaseClient.includes('VITE_SUPABASE_URL'), 'dashboard must allow Supabase URL override');
assert(supabaseClient.includes('VITE_SUPABASE_ANON_KEY'), 'dashboard must allow Supabase anon key override');
assert(!supabaseClient.includes('https://TU_PROYECTO.supabase.co'), 'dashboard must not ship placeholder Supabase URL');
assert(!supabaseClient.includes('TU_LLAVE_ANONIMA'), 'dashboard must not ship placeholder Supabase anon key');

console.log('Dashboard static checks passed.');
