-- ==============================================================================
-- ENLACE360 - ESQUEMA SUPABASE
-- Version: SYSTEM-2026-05-10.1
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Para habilitar C2 seguro, calcula un secreto en Supabase:
-- SELECT encode(digest('CAMBIA_ESTE_TOKEN_ADMIN', 'sha256'), 'hex');
-- ALTER DATABASE postgres SET app.enlace360_admin_secret_sha256 = '<hash>';
-- NOTIFY pgrst, 'reload config';

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
    agent_secret_hash text,
    agent_registered_at timestamp with time zone,
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
    requested_by text DEFAULT 'dashboard',
    created_at timestamp with time zone DEFAULT now(),
    claimed_at timestamp with time zone,
    executed_at timestamp with time zone,
    expires_at timestamp with time zone DEFAULT (now() + interval '10 minutes')
);

-- Migraciones compatibles para bases ya creadas.
ALTER TABLE public.kiosks ADD COLUMN IF NOT EXISTS location text DEFAULT 'Sede Principal';
ALTER TABLE public.kiosks ADD COLUMN IF NOT EXISTS mac_address text;
ALTER TABLE public.kiosks ADD COLUMN IF NOT EXISTS latency_ms integer;
ALTER TABLE public.kiosks ADD COLUMN IF NOT EXISTS integrity_status text DEFAULT 'unknown';
ALTER TABLE public.kiosks ADD COLUMN IF NOT EXISTS integrity_alert text;
ALTER TABLE public.kiosks ADD COLUMN IF NOT EXISTS integrity_checked_at timestamp with time zone;
ALTER TABLE public.kiosks ADD COLUMN IF NOT EXISTS integrity_details jsonb DEFAULT '{}'::jsonb;
ALTER TABLE public.kiosks ADD COLUMN IF NOT EXISTS agent_secret_hash text;
ALTER TABLE public.kiosks ADD COLUMN IF NOT EXISTS agent_registered_at timestamp with time zone;
ALTER TABLE public.kiosks ADD COLUMN IF NOT EXISTS updated_at timestamp with time zone DEFAULT now();
ALTER TABLE public.network_events ADD COLUMN IF NOT EXISTS location text DEFAULT 'Sede Principal';
ALTER TABLE public.remote_commands ADD COLUMN IF NOT EXISTS output_log text;
ALTER TABLE public.remote_commands ADD COLUMN IF NOT EXISTS requested_by text DEFAULT 'dashboard';
ALTER TABLE public.remote_commands ADD COLUMN IF NOT EXISTS claimed_at timestamp with time zone;
ALTER TABLE public.remote_commands ADD COLUMN IF NOT EXISTS executed_at timestamp with time zone;
ALTER TABLE public.remote_commands ADD COLUMN IF NOT EXISTS expires_at timestamp with time zone DEFAULT (now() + interval '10 minutes');

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'remote_commands_status_check'
          AND conrelid = 'public.remote_commands'::regclass
    ) THEN
        ALTER TABLE public.remote_commands
            ADD CONSTRAINT remote_commands_status_check
            CHECK (status IN ('pending', 'in_progress', 'executed', 'failed', 'cancelled', 'expired'));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_kiosks_status_last_heartbeat
    ON public.kiosks (status, last_heartbeat DESC);
CREATE INDEX IF NOT EXISTS idx_network_events_offline_time_desc
    ON public.network_events (offline_time DESC);
CREATE INDEX IF NOT EXISTS idx_network_events_kiosk_offline_desc
    ON public.network_events (kiosk_id, offline_time DESC);
CREATE INDEX IF NOT EXISTS idx_remote_commands_kiosk_created_desc
    ON public.remote_commands (kiosk_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_remote_commands_pending_kiosk
    ON public.remote_commands (kiosk_id, status, created_at)
    WHERE status IN ('pending', 'in_progress');

CREATE OR REPLACE FUNCTION public.enlace360_touch_kiosks_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.enlace360_reject_kiosk_id_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.kiosk_id IS DISTINCT FROM OLD.kiosk_id THEN
        RAISE EXCEPTION 'kiosk_id cannot be changed';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enlace360_kiosks_touch_updated_at ON public.kiosks;
CREATE TRIGGER enlace360_kiosks_touch_updated_at
    BEFORE UPDATE ON public.kiosks
    FOR EACH ROW
    EXECUTE FUNCTION public.enlace360_touch_kiosks_updated_at();

DROP TRIGGER IF EXISTS enlace360_kiosks_reject_id_change ON public.kiosks;
CREATE TRIGGER enlace360_kiosks_reject_id_change
    BEFORE UPDATE ON public.kiosks
    FOR EACH ROW
    EXECUTE FUNCTION public.enlace360_reject_kiosk_id_change();

CREATE OR REPLACE FUNCTION public.enlace360_sha256(p_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
STRICT
SET search_path = public, extensions, pg_temp
AS $$
    SELECT encode(digest(p_value, 'sha256'), 'hex');
$$;

CREATE OR REPLACE FUNCTION public.enlace360_request_header(p_name text)
RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    raw_headers text;
    headers jsonb;
    found_value text;
BEGIN
    raw_headers := current_setting('request.headers', true);
    IF raw_headers IS NULL OR raw_headers = '' THEN
        RETURN NULL;
    END IF;

    headers := raw_headers::jsonb;
    SELECT value
      INTO found_value
      FROM jsonb_each_text(headers)
     WHERE lower(key) = lower(p_name)
     LIMIT 1;

    RETURN nullif(found_value, '');
EXCEPTION WHEN others THEN
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.enlace360_request_agent_secret_hash()
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT CASE
        WHEN public.enlace360_request_header('x-enlace360-agent-secret') IS NULL THEN NULL
        ELSE public.enlace360_sha256(public.enlace360_request_header('x-enlace360-agent-secret'))
    END;
$$;

CREATE OR REPLACE FUNCTION public.enlace360_admin_secret_ok(p_admin_secret text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    expected_hash text;
BEGIN
    expected_hash := current_setting('app.enlace360_admin_secret_sha256', true);
    RETURN expected_hash IS NOT NULL
       AND expected_hash <> ''
       AND public.enlace360_sha256(coalesce(p_admin_secret, '')) = expected_hash;
END;
$$;

CREATE OR REPLACE FUNCTION public.enlace360_agent_secret_ok(p_kiosk_id text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    current_hash text;
    registered_hash text;
BEGIN
    current_hash := public.enlace360_request_agent_secret_hash();
    IF current_hash IS NULL THEN
        RETURN false;
    END IF;

    SELECT agent_secret_hash
      INTO registered_hash
      FROM public.kiosks
     WHERE kiosk_id = p_kiosk_id;

    RETURN registered_hash IS NOT NULL AND registered_hash = current_hash;
END;
$$;

CREATE OR REPLACE FUNCTION public.enlace360_submit_kiosk_heartbeat(
    p_kiosk_id text,
    p_client_name text,
    p_location text,
    p_status text,
    p_last_heartbeat timestamp with time zone,
    p_uptime text,
    p_ip_address text,
    p_mac_address text,
    p_latency_ms integer,
    p_integrity_status text,
    p_integrity_alert text,
    p_integrity_checked_at timestamp with time zone,
    p_integrity_details jsonb,
    p_agent_secret_hash text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    current_hash text;
    registered_hash text;
BEGIN
    current_hash := public.enlace360_request_agent_secret_hash();
    IF current_hash IS NULL OR current_hash <> p_agent_secret_hash THEN
        RAISE EXCEPTION 'agent secret is missing or invalid';
    END IF;

    SELECT agent_secret_hash
      INTO registered_hash
      FROM public.kiosks
     WHERE kiosk_id = p_kiosk_id
     FOR UPDATE;

    IF registered_hash IS NOT NULL AND registered_hash <> current_hash THEN
        RAISE EXCEPTION 'agent secret does not match registered kiosk';
    END IF;

    INSERT INTO public.kiosks (
        kiosk_id,
        client_name,
        location,
        status,
        last_heartbeat,
        uptime,
        ip_address,
        mac_address,
        latency_ms,
        integrity_status,
        integrity_alert,
        integrity_checked_at,
        integrity_details,
        agent_secret_hash,
        agent_registered_at,
        updated_at
    ) VALUES (
        p_kiosk_id,
        p_client_name,
        coalesce(p_location, 'Sede Principal'),
        coalesce(p_status, 'online'),
        p_last_heartbeat,
        p_uptime,
        p_ip_address,
        p_mac_address,
        p_latency_ms,
        coalesce(p_integrity_status, 'unknown'),
        p_integrity_alert,
        p_integrity_checked_at,
        coalesce(p_integrity_details, '{}'::jsonb),
        current_hash,
        now(),
        now()
    )
    ON CONFLICT (kiosk_id) DO UPDATE SET
        client_name = EXCLUDED.client_name,
        location = EXCLUDED.location,
        status = EXCLUDED.status,
        last_heartbeat = EXCLUDED.last_heartbeat,
        uptime = EXCLUDED.uptime,
        ip_address = EXCLUDED.ip_address,
        mac_address = EXCLUDED.mac_address,
        latency_ms = EXCLUDED.latency_ms,
        integrity_status = EXCLUDED.integrity_status,
        integrity_alert = EXCLUDED.integrity_alert,
        integrity_checked_at = EXCLUDED.integrity_checked_at,
        integrity_details = EXCLUDED.integrity_details,
        agent_secret_hash = coalesce(public.kiosks.agent_secret_hash, EXCLUDED.agent_secret_hash),
        agent_registered_at = coalesce(public.kiosks.agent_registered_at, EXCLUDED.agent_registered_at),
        updated_at = now();
END;
$$;

CREATE OR REPLACE FUNCTION public.enlace360_report_network_event(
    p_kiosk_id text,
    p_client_name text,
    p_location text,
    p_offline_time timestamp with time zone,
    p_online_time timestamp with time zone,
    p_probable_cause text,
    p_diagnostics jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    inserted_id uuid;
BEGIN
    IF NOT public.enlace360_agent_secret_ok(p_kiosk_id) THEN
        RAISE EXCEPTION 'agent secret does not match registered kiosk';
    END IF;

    INSERT INTO public.network_events (
        kiosk_id,
        client_name,
        location,
        offline_time,
        online_time,
        probable_cause,
        diagnostics
    ) VALUES (
        p_kiosk_id,
        p_client_name,
        coalesce(p_location, 'Sede Principal'),
        p_offline_time,
        p_online_time,
        p_probable_cause,
        p_diagnostics
    )
    RETURNING id INTO inserted_id;

    RETURN inserted_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.enlace360_enqueue_remote_command(
    p_admin_secret text,
    p_kiosk_id text,
    p_command_string text,
    p_requested_by text DEFAULT 'dashboard'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    inserted_id uuid;
BEGIN
    IF NOT public.enlace360_admin_secret_ok(p_admin_secret) THEN
        RAISE EXCEPTION 'invalid C2 admin secret';
    END IF;

    IF p_command_string IS NULL OR length(trim(p_command_string)) = 0 THEN
        RAISE EXCEPTION 'command_string cannot be empty';
    END IF;

    IF length(p_command_string) > 4000 THEN
        RAISE EXCEPTION 'command_string exceeds 4000 characters';
    END IF;

    INSERT INTO public.remote_commands (
        kiosk_id,
        command_string,
        status,
        requested_by,
        expires_at
    ) VALUES (
        p_kiosk_id,
        p_command_string,
        'pending',
        coalesce(nullif(p_requested_by, ''), 'dashboard'),
        now() + interval '10 minutes'
    )
    RETURNING id INTO inserted_id;

    RETURN inserted_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.enlace360_list_remote_commands(
    p_admin_secret text,
    p_kiosk_id text,
    p_limit integer DEFAULT 20
)
RETURNS TABLE (
    id uuid,
    kiosk_id text,
    command_string text,
    status text,
    output_log text,
    requested_by text,
    created_at timestamp with time zone,
    claimed_at timestamp with time zone,
    executed_at timestamp with time zone,
    expires_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT public.enlace360_admin_secret_ok(p_admin_secret) THEN
        RAISE EXCEPTION 'invalid C2 admin secret';
    END IF;

    RETURN QUERY
    SELECT rc.id,
           rc.kiosk_id,
           rc.command_string,
           rc.status,
           rc.output_log,
           rc.requested_by,
           rc.created_at,
           rc.claimed_at,
           rc.executed_at,
           rc.expires_at
      FROM public.remote_commands rc
     WHERE rc.kiosk_id = p_kiosk_id
     ORDER BY rc.created_at DESC
     LIMIT least(greatest(coalesce(p_limit, 20), 1), 100);
END;
$$;

CREATE OR REPLACE FUNCTION public.enlace360_claim_remote_commands(
    p_kiosk_id text,
    p_limit integer DEFAULT 5
)
RETURNS TABLE (
    id uuid,
    command_string text,
    created_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT public.enlace360_agent_secret_ok(p_kiosk_id) THEN
        RAISE EXCEPTION 'agent secret does not match registered kiosk';
    END IF;

    UPDATE public.remote_commands
       SET status = 'expired'
     WHERE kiosk_id = p_kiosk_id
       AND status = 'pending'
       AND expires_at IS NOT NULL
       AND expires_at <= now();

    RETURN QUERY
    WITH picked AS (
        SELECT rc.id
          FROM public.remote_commands rc
         WHERE rc.kiosk_id = p_kiosk_id
           AND rc.status = 'pending'
           AND (rc.expires_at IS NULL OR rc.expires_at > now())
         ORDER BY rc.created_at ASC
         LIMIT least(greatest(coalesce(p_limit, 5), 1), 10)
         FOR UPDATE SKIP LOCKED
    ),
    updated AS (
        UPDATE public.remote_commands rc
           SET status = 'in_progress',
               claimed_at = now()
          FROM picked
         WHERE rc.id = picked.id
         RETURNING rc.id, rc.command_string, rc.created_at
    )
    SELECT updated.id, updated.command_string, updated.created_at
      FROM updated;
END;
$$;

CREATE OR REPLACE FUNCTION public.enlace360_complete_remote_command(
    p_command_id uuid,
    p_kiosk_id text,
    p_status text,
    p_output_log text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT public.enlace360_agent_secret_ok(p_kiosk_id) THEN
        RAISE EXCEPTION 'agent secret does not match registered kiosk';
    END IF;

    IF p_status NOT IN ('executed', 'failed', 'cancelled') THEN
        RAISE EXCEPTION 'invalid command completion status';
    END IF;

    UPDATE public.remote_commands
       SET status = p_status,
           output_log = left(coalesce(p_output_log, ''), 4000),
           executed_at = now()
     WHERE id = p_command_id
       AND kiosk_id = p_kiosk_id
       AND status = 'in_progress';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'remote command was not claimed by this kiosk';
    END IF;
END;
$$;

ALTER TABLE public.kiosks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.network_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.remote_commands ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Permitir lectura publica a kioscos" ON public.kiosks;
DROP POLICY IF EXISTS "Permitir insertar kioscos desde API" ON public.kiosks;
DROP POLICY IF EXISTS "Permitir actualizar kioscos desde API" ON public.kiosks;
DROP POLICY IF EXISTS "Permitir heartbeat legacy temporal insert" ON public.kiosks;
DROP POLICY IF EXISTS "Permitir heartbeat legacy temporal update" ON public.kiosks;
DROP POLICY IF EXISTS "Permitir lectura publica a eventos" ON public.network_events;
DROP POLICY IF EXISTS "Permitir insertar eventos desde API" ON public.network_events;
DROP POLICY IF EXISTS "Permitir leer comandos remotos" ON public.remote_commands;
DROP POLICY IF EXISTS "Permitir insertar comandos remotos" ON public.remote_commands;
DROP POLICY IF EXISTS "Permitir actualizar comandos remotos" ON public.remote_commands;

CREATE POLICY "Permitir lectura publica a kioscos"
    ON public.kiosks
    FOR SELECT
    USING (true);

CREATE POLICY "Permitir lectura publica a eventos"
    ON public.network_events
    FOR SELECT
    USING (true);

-- Puente temporal para agentes v3.5/v3.6: solo heartbeat legacy.
-- No reabre remote_commands ni permite tomar filas ya registradas con AgentSecret.
CREATE POLICY "Permitir heartbeat legacy temporal insert"
    ON public.kiosks
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (
        agent_secret_hash IS NULL
        AND agent_registered_at IS NULL
        AND kiosk_id IS NOT NULL
        AND client_name IS NOT NULL
        AND status IN ('online', 'offline', 'degraded')
        AND last_heartbeat IS NOT NULL
        AND last_heartbeat >= now() - interval '24 hours'
        AND last_heartbeat <= now() + interval '5 minutes'
        AND (latency_ms IS NULL OR latency_ms >= 0)
    );

CREATE POLICY "Permitir heartbeat legacy temporal update"
    ON public.kiosks
    FOR UPDATE
    TO anon, authenticated
    USING (agent_secret_hash IS NULL)
    WITH CHECK (
        agent_secret_hash IS NULL
        AND agent_registered_at IS NULL
        AND kiosk_id IS NOT NULL
        AND client_name IS NOT NULL
        AND status IN ('online', 'offline', 'degraded')
        AND last_heartbeat IS NOT NULL
        AND last_heartbeat >= now() - interval '24 hours'
        AND last_heartbeat <= now() + interval '5 minutes'
        AND (latency_ms IS NULL OR latency_ms >= 0)
    );

-- Sin politicas anonimas para remote_commands: todo C2 pasa por RPC con secreto.

REVOKE ALL ON public.kiosks FROM anon, authenticated;
REVOKE ALL ON public.network_events FROM anon, authenticated;
REVOKE ALL ON public.remote_commands FROM anon, authenticated;

GRANT SELECT (
    kiosk_id,
    client_name,
    location,
    status,
    last_heartbeat,
    uptime,
    ip_address,
    mac_address,
    latency_ms,
    integrity_status,
    integrity_alert,
    integrity_checked_at,
    integrity_details,
    created_at,
    updated_at
) ON public.kiosks TO anon, authenticated;

GRANT INSERT (
    kiosk_id,
    client_name,
    location,
    status,
    last_heartbeat,
    uptime,
    ip_address,
    mac_address,
    latency_ms
) ON public.kiosks TO anon, authenticated;

GRANT UPDATE (
    kiosk_id,
    client_name,
    location,
    status,
    last_heartbeat,
    uptime,
    ip_address,
    mac_address,
    latency_ms
) ON public.kiosks TO anon, authenticated;

GRANT SELECT (
    id,
    kiosk_id,
    client_name,
    location,
    offline_time,
    online_time,
    probable_cause,
    diagnostics,
    created_at
) ON public.network_events TO anon, authenticated;

GRANT EXECUTE ON FUNCTION public.enlace360_submit_kiosk_heartbeat(
    text, text, text, text, timestamp with time zone, text, text, text, integer, text, text, timestamp with time zone, jsonb, text
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enlace360_report_network_event(
    text, text, text, timestamp with time zone, timestamp with time zone, text, jsonb
) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enlace360_enqueue_remote_command(text, text, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enlace360_list_remote_commands(text, text, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enlace360_claim_remote_commands(text, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enlace360_complete_remote_command(uuid, text, text, text) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
