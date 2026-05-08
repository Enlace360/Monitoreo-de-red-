-- ==============================================================================
-- ENLACE360 - ESQUEMA SUPABASE
-- Version: SYSTEM-2026-05-08.1
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. Estado en tiempo real de cada kiosco/agente.
CREATE TABLE IF NOT EXISTS public.kiosks (
    kiosk_id text PRIMARY KEY,
    client_name text NOT NULL,
    location text DEFAULT 'Sede Principal',
    status text NOT NULL DEFAULT 'online',
    last_heartbeat timestamp with time zone,
    uptime text,
    ip_address text,
    mac_address text,
    latency_ms integer,
    integrity_status text DEFAULT 'unknown',
    integrity_alert text,
    integrity_checked_at timestamp with time zone,
    integrity_details jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);

-- 2. Historial de caidas y eventos de integridad.
CREATE TABLE IF NOT EXISTS public.network_events (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    kiosk_id text REFERENCES public.kiosks(kiosk_id) ON DELETE CASCADE,
    client_name text NOT NULL,
    location text DEFAULT 'Sede Principal',
    offline_time timestamp with time zone NOT NULL,
    online_time timestamp with time zone,
    probable_cause text,
    diagnostics jsonb,
    created_at timestamp with time zone DEFAULT now()
);

-- 3. Cola C2 para terminal remota y acciones del dashboard.
CREATE TABLE IF NOT EXISTS public.remote_commands (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    kiosk_id text REFERENCES public.kiosks(kiosk_id) ON DELETE CASCADE,
    command_string text NOT NULL,
    status text NOT NULL DEFAULT 'pending',
    output_log text,
    created_at timestamp with time zone DEFAULT now(),
    executed_at timestamp with time zone
);

-- Migraciones compatibles para bases ya creadas.
ALTER TABLE public.kiosks ADD COLUMN IF NOT EXISTS location text DEFAULT 'Sede Principal';
ALTER TABLE public.kiosks ADD COLUMN IF NOT EXISTS mac_address text;
ALTER TABLE public.kiosks ADD COLUMN IF NOT EXISTS latency_ms integer;
ALTER TABLE public.kiosks ADD COLUMN IF NOT EXISTS integrity_status text DEFAULT 'unknown';
ALTER TABLE public.kiosks ADD COLUMN IF NOT EXISTS integrity_alert text;
ALTER TABLE public.kiosks ADD COLUMN IF NOT EXISTS integrity_checked_at timestamp with time zone;
ALTER TABLE public.kiosks ADD COLUMN IF NOT EXISTS integrity_details jsonb DEFAULT '{}'::jsonb;
ALTER TABLE public.kiosks ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone DEFAULT now();
ALTER TABLE public.network_events ADD COLUMN IF NOT EXISTS location text DEFAULT 'Sede Principal';

ALTER TABLE public.kiosks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.network_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.remote_commands ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Permitir lectura publica a kioscos" ON public.kiosks;
DROP POLICY IF EXISTS "Permitir insertar kioscos desde API" ON public.kiosks;
DROP POLICY IF EXISTS "Permitir actualizar kioscos desde API" ON public.kiosks;
DROP POLICY IF EXISTS "Permitir lectura publica a eventos" ON public.network_events;
DROP POLICY IF EXISTS "Permitir insertar eventos desde API" ON public.network_events;
DROP POLICY IF EXISTS "Permitir leer comandos remotos" ON public.remote_commands;
DROP POLICY IF EXISTS "Permitir insertar comandos remotos" ON public.remote_commands;
DROP POLICY IF EXISTS "Permitir actualizar comandos remotos" ON public.remote_commands;

CREATE POLICY "Permitir lectura publica a kioscos" ON public.kiosks FOR SELECT USING (true);
CREATE POLICY "Permitir insertar kioscos desde API" ON public.kiosks FOR INSERT WITH CHECK (true);
CREATE POLICY "Permitir actualizar kioscos desde API" ON public.kiosks FOR UPDATE USING (true);
CREATE POLICY "Permitir lectura publica a eventos" ON public.network_events FOR SELECT USING (true);
CREATE POLICY "Permitir insertar eventos desde API" ON public.network_events FOR INSERT WITH CHECK (true);
CREATE POLICY "Permitir leer comandos remotos" ON public.remote_commands FOR SELECT USING (true);
CREATE POLICY "Permitir insertar comandos remotos" ON public.remote_commands FOR INSERT WITH CHECK (true);
CREATE POLICY "Permitir actualizar comandos remotos" ON public.remote_commands FOR UPDATE USING (true);
