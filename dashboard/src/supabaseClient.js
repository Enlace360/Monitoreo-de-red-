import { createClient } from '@supabase/supabase-js'

// La anon key es publica por diseño en Supabase; las variables de entorno
// permiten cambiar de proyecto sin tocar el codigo fuente.
const defaultSupabaseUrl = 'https://zhvykvpixpkjegfxgwer.supabase.co'
const defaultSupabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpodnlrdnBpeHBramVnZnhnd2VyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc0ODI3NTksImV4cCI6MjA5MzA1ODc1OX0.kE0BA4IyldzvX4XfhF3bHAARTRDkAlqSgAlM6Am5YdI'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || defaultSupabaseUrl
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || defaultSupabaseAnonKey

export const supabase = createClient(supabaseUrl, supabaseAnonKey)
