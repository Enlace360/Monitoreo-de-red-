# Enlace360 Dashboard

Dashboard React/Vite publicado en Cloudflare Pages para monitoreo de kioscos Enlace360.

## Stack

- React 19
- Vite 8
- Supabase JS
- Lucide React

## Desarrollo Local

```bash
npm install
npm run dev
```

El cliente Supabase usa valores por defecto del proyecto productivo y permite override con:

```text
VITE_SUPABASE_URL
VITE_SUPABASE_ANON_KEY
```

## Checks

Desde la raiz del repo:

```bash
node tests/dashboard_kiosk_time_check.mjs
node tests/dashboard_static_check.cjs
```

Desde `dashboard/`:

```bash
npm run lint
npm run build
```

## Publicacion

El build esperado queda en:

```text
dashboard/dist/
```

Cloudflare Pages debe publicar el resultado de `npm run build` desde `dashboard/`, o usar la configuracion root `wrangler.jsonc` con `assets.directory = "dashboard/dist"`.

El contador visible de cada tarjeta muestra tiempo de sesion online (`Online ...`). El uptime de Windows se conserva como metadata secundaria en tooltip.
