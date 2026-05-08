const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const schema = fs.readFileSync(path.join(root, 'supabase_schema.sql'), 'utf8');

function includes(expected, label = expected) {
  assert(schema.includes(expected), `schema must include: ${label}`);
}

includes('integrity_status text', 'kiosks integrity status column');
includes('SYSTEM-2026-05-08.1', 'schema version');
includes('integrity_alert text', 'kiosks integrity alert column');
includes('integrity_checked_at timestamp with time zone', 'kiosks integrity checked timestamp column');
includes('integrity_details jsonb', 'kiosks integrity details column');
includes('CREATE TABLE IF NOT EXISTS public.remote_commands', 'remote commands table');
includes('ALTER TABLE public.kiosks ADD COLUMN IF NOT EXISTS integrity_status', 'backward-compatible integrity migration');
includes('ALTER TABLE public.kiosks ADD COLUMN IF NOT EXISTS integrity_details', 'backward-compatible integrity details migration');
includes('CREATE POLICY "Permitir insertar comandos remotos"', 'remote command insert policy');
includes('CREATE POLICY "Permitir actualizar comandos remotos"', 'remote command update policy');

console.log('Schema static checks passed.');
