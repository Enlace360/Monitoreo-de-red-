-- ==============================================================================
-- KIOSK NETWORK MONITOR - ESQUEMA DE BASE DE DATOS SUPABASE (ACTUALIZADO)
-- ==============================================================================

-- Si ya creaste las tablas antes, solo corre estas dos lineas para agregar las sucursales:
-- ALTER TABLE public.kiosks ADD COLUMN location text DEFAULT 'Sede Principal';
-- ALTER TABLE public.network_events ADD COLUMN location text DEFAULT 'Sede Principal';

-- Si es la primera vez que creas las tablas, usa este código completo:

-- 1. Crear tabla de Kioscos (Estado en tiempo real)
CREATE TABLE public.kiosks (
    kiosk_id text PRIMARY KEY,            
    client_name text NOT NULL,            
    location text DEFAULT 'Sede Principal', -- NUEVO: Sucursal del equipo
    status text NOT NULL DEFAULT 'online',
    last_heartbeat timestamp with time zone, 
    uptime text,                          
    ip_address text,                      
    created_at timestamp with time zone DEFAULT now()
);

-- 2. Crear tabla de Eventos (Historial de Caídas)
CREATE TABLE public.network_events (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    kiosk_id text REFERENCES public.kiosks(kiosk_id) ON DELETE CASCADE,
    client_name text NOT NULL,
    location text DEFAULT 'Sede Principal', -- NUEVO: Sucursal donde ocurrió el evento
    offline_time timestamp with time zone NOT NULL,
    online_time timestamp with time zone,
    probable_cause text,
    diagnostics jsonb,                    
    created_at timestamp with time zone DEFAULT now()
);

-- Seguridad (RLS)
ALTER TABLE public.kiosks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.network_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Permitir lectura publica a kioscos" ON public.kiosks FOR SELECT USING (true);
CREATE POLICY "Permitir lectura publica a eventos" ON public.network_events FOR SELECT USING (true);
CREATE POLICY "Permitir insertar kioscos desde API" ON public.kiosks FOR INSERT WITH CHECK (true);
CREATE POLICY "Permitir actualizar kioscos desde API" ON public.kiosks FOR UPDATE USING (true);
CREATE POLICY "Permitir insertar eventos desde API" ON public.network_events FOR INSERT WITH CHECK (true);
