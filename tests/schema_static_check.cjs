const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const schema = fs.readFileSync(path.join(root, 'supabase_schema.sql'), 'utf8');

function includes(expected, label = expected) {
  assert(schema.includes(expected), `schema must include: ${label}`);
}

function notIncludes(unexpected, label = unexpected) {
  assert(!schema.includes(unexpected), `schema must not include: ${label}`);
}

includes('integrity_status text', 'kiosks integrity status column');
includes('SYSTEM-2026-05-10.1', 'schema version');
includes('integrity_alert text', 'kiosks integrity alert column');
includes('integrity_checked_at timestamp with time zone', 'kiosks integrity checked timestamp column');
includes('integrity_details jsonb', 'kiosks integrity details column');
includes('agent_secret_hash text', 'kiosks agent secret hash column');
includes('CREATE TABLE IF NOT EXISTS public.remote_commands', 'remote commands table');
includes('claimed_at timestamp with time zone', 'remote commands claim timestamp');
includes('expires_at timestamp with time zone', 'remote commands expiration timestamp');
includes('ALTER TABLE public.kiosks ADD COLUMN IF NOT EXISTS integrity_status', 'backward-compatible integrity migration');
includes('ALTER TABLE public.kiosks ADD COLUMN IF NOT EXISTS integrity_details', 'backward-compatible integrity details migration');
includes('CREATE OR REPLACE FUNCTION public.enlace360_submit_kiosk_heartbeat', 'secure heartbeat RPC');
includes('CREATE OR REPLACE FUNCTION public.enlace360_report_network_event', 'secure network event RPC');
includes('CREATE OR REPLACE FUNCTION public.enlace360_enqueue_remote_command', 'secure command enqueue RPC');
includes('CREATE OR REPLACE FUNCTION public.enlace360_claim_remote_commands', 'secure command claim RPC');
includes('CREATE OR REPLACE FUNCTION public.enlace360_complete_remote_command', 'secure command completion RPC');
includes('CREATE OR REPLACE FUNCTION public.enlace360_touch_kiosks_updated_at', 'kiosks updated_at trigger function');
includes('CREATE OR REPLACE FUNCTION public.enlace360_reject_kiosk_id_change', 'kiosks id-change guard');
includes('Permitir heartbeat legacy temporal insert', 'temporary legacy heartbeat insert bridge');
includes('Permitir heartbeat legacy temporal update', 'temporary legacy heartbeat update bridge');
includes('agent_secret_hash IS NULL', 'legacy bridge only applies to unregistered kiosks');
includes('GRANT INSERT (', 'legacy heartbeat insert column grant');
includes('GRANT UPDATE (', 'legacy heartbeat update column grant');
includes('GRANT EXECUTE ON FUNCTION public.enlace360_enqueue_remote_command', 'dashboard RPC grant');
includes('REVOKE ALL ON public.remote_commands FROM anon, authenticated', 'remote commands table blocked from direct anon/auth access');
includes('GRANT EXECUTE ON FUNCTION public.enlace360_claim_remote_commands(text, integer) TO anon, authenticated', 'agent RPC grant');
includes('CREATE INDEX IF NOT EXISTS idx_remote_commands_pending_kiosk', 'pending command index');
includes('CREATE INDEX IF NOT EXISTS idx_network_events_kiosk_offline_desc', 'event history index');
notIncludes('CREATE POLICY "Permitir insertar comandos remotos"', 'direct remote command insert policy');
notIncludes('CREATE POLICY "Permitir actualizar comandos remotos"', 'direct remote command update policy');
notIncludes('CREATE POLICY "Permitir leer comandos remotos"', 'direct remote command read policy');
notIncludes('FOR INSERT WITH CHECK (true)', 'open insert RLS policy');
notIncludes('FOR UPDATE USING (true)', 'open update RLS policy');

console.log('Schema static checks passed.');
