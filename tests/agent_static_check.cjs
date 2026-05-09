const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const rootAgentPath = path.join(root, 'Agente_Enlace360_Service.ps1');
const agentPath = path.join(root, 'Enlace360_SYSTEM_20260503_v6', 'Agente_Enlace360_Service.ps1');
assert.strictEqual(
  fs.readFileSync(rootAgentPath, 'utf8'),
  fs.readFileSync(agentPath, 'utf8'),
  'root Agente_Enlace360_Service.ps1 must match SYSTEM kit agent for dashboard raw update URL',
);
const source = fs.readFileSync(agentPath, 'utf8');
const label = path.relative(root, agentPath);

function includes(expected, detail = expected) {
  assert(source.includes(expected), `${label} must include: ${detail}`);
}

function notIncludes(unexpected, detail = unexpected) {
  assert(!source.includes(unexpected), `${label} must not include: ${detail}`);
}

includes('$AgentVersion = "v3.8"', 'agent v3.8');
includes('$SupabaseUrl = "https://zhvykvpixpkjegfxgwer.supabase.co"', 'current Supabase URL');
includes('$HttpTimeoutSecs = 10', 'bounded HTTP timeout');
includes('$AgentSecret', 'agent has per-install secret');
includes('X-Enlace360-Agent-Secret', 'agent sends secret header to Supabase RPC');
includes('Function Get-Sha256Hex', 'agent hashes local secret for registration');
includes('Global\\Enlace360AgentDaemon', 'single instance mutex');
includes('$IntegrityFile = Join-Path $LogDir "integrity_state.json"', 'local integrity state file');
includes('Function Invoke-EnlaceRestJson', 'hardened REST helper');
includes('Start-Job -ScriptBlock', 'killable jobs for REST/C2 isolation');
includes('Wait-Job -Job $job -Timeout ($HttpTimeoutSecs + 3)', 'hard REST timeout');
includes('Stop-Job -Job $job -Force', 'stop hung REST jobs');
includes('[System.Net.HttpWebRequest][System.Net.WebRequest]::Create($Uri)', 'HttpWebRequest hard timeout');
includes('Function Check-RemoteCommands', 'C2 lives in agent');
includes('/rest/v1/rpc/enlace360_claim_remote_commands', 'agent claims remote commands through RPC');
includes('/rest/v1/rpc/enlace360_complete_remote_command', 'agent completes remote commands through RPC');
includes('status=eq.pending', 'agent only pulls pending commands');
includes('Wait-Job -Job $job -Timeout 60', 'C2 command timeout');
includes('p_output_log = $output.Trim()', 'C2 sends command output through RPC');
includes('p_status = $execStatus', 'C2 sends completion status through RPC');
includes('Function Update-KioskStatus', 'heartbeat function');
includes('Function Get-AgentIntegrity', 'agent integrity inventory');
includes('Function Report-IntegrityEvent', 'integrity event reporting');
includes('Function Submit-KioskPayload', 'kiosk payload fallback sender');
includes('integrity_status', 'heartbeat reports integrity status');
includes('integrity_alert', 'heartbeat reports integrity alert');
includes('integrity_details', 'heartbeat reports integrity details');
includes('INTEGRIDAD AGENTE', 'integrity events use explicit cause');
includes('Enlace360Agent', 'service presence included in integrity');
includes('[HEARTBEAT] Preparando payload', 'heartbeat payload checkpoint');
includes('[HEARTBEAT] Enviando estado', 'heartbeat send checkpoint');
includes('return $true', 'heartbeat success result');
includes('return $false', 'heartbeat failure result');
includes('No se actualiza last_heartbeat local porque Supabase no confirmo', 'local heartbeat only after Supabase confirmation');
includes('Function Report-NetworkIncident', 'network_events reporting');
includes('/rest/v1/rpc/enlace360_report_network_event', 'network_events RPC endpoint');
includes('Function Attempt-SelfHealing', 'network self-healing');
includes('Restart-Computer -Force', 'Lazaro reboot protocol');
includes('lazaro_count.txt', 'Lazaro daily cap state');
includes('Check-SelfUpdate', 'hash hot-swap');
includes('[ERROR] Error inesperado en bucle principal', 'daemon loop survives unexpected errors');

notIncludes('Enlace360_C2_Poller.ps1', 'external C2 poller dependency');
notIncludes('-EncodedCommand', 'encoded scheduled payload');
notIncludes('.dat', 'legacy dat payloads');
notIncludes('C:\\KioskNetMonitor', 'legacy install path');

console.log('Agent static checks passed.');
