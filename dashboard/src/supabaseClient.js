import { createClient } from '@supabase/supabase-js'

// Usa variables de entorno o valores por defecto para pruebas
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'https://TU_PROYECTO.supabase.co'
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || 'TU_LLAVE_ANONIMA'

export const supabase = createClient(supabaseUrl, supabaseAnonKey)
