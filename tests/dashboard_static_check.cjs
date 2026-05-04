const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const app = fs.readFileSync(path.join(root, 'dashboard', 'src', 'App.jsx'), 'utf8');

function includes(expected, label = expected) {
  assert(app.includes(expected), `dashboard must include: ${label}`);
}

function notIncludes(unexpected, label = unexpected) {
  assert(!app.includes(unexpected), `dashboard must not include: ${label}`);
}

includes('const AGENT_UPDATE_COMMAND =', 'shared update command constant');
includes('C:\\\\ProgramData\\\\Enlace360\\\\Agent', 'SYSTEM install path in update command');
includes('agent_payload.cache', 'cache update in dashboard command');
includes('[Convert]::ToBase64String([System.IO.File]::ReadAllBytes($agent))', 'dashboard refreshes cache after agent download');
includes('raw.githubusercontent.com/Enlace360/Monitoreo-de-red-/main/Agente_Enlace360_Service.ps1', 'root raw agent update URL');
includes('sendCommand(AGENT_UPDATE_COMMAND)', 'single-kiosk update uses shared command');
includes('command_string: AGENT_UPDATE_COMMAND', 'bulk update uses shared command');
includes('const targetKiosks = filteredKiosks', 'bulk update uses visible filtered kiosks');
includes('targetKiosks.length === 0', 'bulk update handles empty list');
notIncludes('C:\\\\KioskNetMonitor\\\\Agente_Enlace360_Service.ps1', 'legacy update path');
notIncludes('kiosks.length', 'undefined kiosks variable');
notIncludes('for (const kiosk of kiosks)', 'undefined kiosks loop');

console.log('Dashboard static checks passed.');
