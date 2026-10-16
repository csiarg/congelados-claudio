# Congelados Claudio · Sistema de gestión

Ventas, stock por camión, cuenta corriente y pedidos por WhatsApp.
Supabase (base de datos) + Netlify (web).

```
frontend/            → la web que publica Netlify (HTML + JS)
  config.js          → URL y anon key de Supabase (públicas)
netlify/functions/   → funciones de servidor (WhatsApp)
database/            → scripts SQL de Supabase (ver database/LEEME.md)
netlify.toml         → configuración de Netlify
```

Cada `git push` a `main` publica automáticamente en Netlify.
