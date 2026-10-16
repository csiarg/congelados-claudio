// Congelados Claudio · utilidades comunes
(function () {
  const cfg = window.APP_CONFIG || {};
  if (!window.supabase || !cfg.SUPABASE_URL) {
    document.body.innerHTML = '<p style="padding:24px">Error de configuración: revisá config.js</p>';
    return;
  }

  const sb = window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY);

  const $ = (sel, el = document) => el.querySelector(sel);
  const $$ = (sel, el = document) => Array.from(el.querySelectorAll(sel));

  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  const fmtPesos = new Intl.NumberFormat('es-AR', { style: 'currency', currency: 'ARS', minimumFractionDigits: 2 });
  const pesos = (n) => fmtPesos.format(Number(n) || 0);
  const cant = (n) => Number(n || 0).toLocaleString('es-AR', { maximumFractionDigits: 3 });
  const fecha = (f) => f ? new Date(f).toLocaleString('es-AR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) : '';
  const fechaCorta = (f) => f ? new Date(f).toLocaleDateString('es-AR', { day: '2-digit', month: '2-digit', year: '2-digit' }) : '';

  // Texto seguro para filtros de PostgREST (or=...)
  const limpiarBusqueda = (t) => String(t || '').replace(/[,()*%\\]/g, ' ').trim();

  let toastTimer;
  function toast(msg, tipo = 'info', ms = 3200) {
    let el = $('#toast');
    if (!el) { el = document.createElement('div'); el.id = 'toast'; el.setAttribute('role', 'status'); document.body.appendChild(el); }
    el.textContent = msg;
    el.className = tipo;
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { el.hidden = true; }, ms);
  }

  function mensajeError(error) {
    const m = (error && (error.message || error.error_description || error.msg)) || 'Error desconocido';
    if (/Failed to fetch|NetworkError/i.test(m)) return 'Sin conexión. Revisá internet e intentá de nuevo.';
    if (/JWT expired/i.test(m)) return 'La sesión venció. Volvé a entrar.';
    if (/Invalid login credentials/i.test(m)) return 'Mail o contraseña incorrectos.';
    if (/Email not confirmed/i.test(m)) return 'El usuario no está confirmado. Pedile al administrador que lo confirme.';
    if (/permission denied|row-level security/i.test(m)) return 'No tenés permiso para hacer esto.';
    return m;
  }

  async function rpc(nombre, params = {}) {
    const { data, error } = await sb.rpc(nombre, params);
    if (error) throw new Error(mensajeError(error));
    return data;
  }

  async function consulta(promesa) {
    const { data, error } = await promesa;
    if (error) throw new Error(mensajeError(error));
    return data;
  }

  // Bloquea un botón mientras corre una acción y muestra errores
  async function conBoton(boton, fn) {
    const texto = boton ? boton.innerHTML : '';
    if (boton) { boton.disabled = true; boton.innerHTML = 'Procesando…'; }
    try { return await fn(); }
    catch (e) { toast(e.message || String(e), 'error', 6000); }
    finally { if (boton) { boton.disabled = false; boton.innerHTML = texto; } }
  }

  // Devuelve { session, perfil } o redirige al login
  async function exigirSesion() {
    const { data: { session } } = await sb.auth.getSession();
    if (!session) { location.replace('index.html'); return null; }
    const { data: perfil, error } = await sb.from('perfiles').select('*').eq('user_id', session.user.id).maybeSingle();
    if (error || !perfil || !perfil.activo) {
      await sb.auth.signOut();
      location.replace('index.html?sin_acceso=1');
      return null;
    }
    return { session, perfil };
  }

  function debounce(fn, ms = 250) {
    let t;
    return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); };
  }

  const guardar = (k, v) => { try { localStorage.setItem('cc_' + k, JSON.stringify(v)); } catch (e) { /* sin almacenamiento */ } };
  const leer = (k, def = null) => { try { const v = localStorage.getItem('cc_' + k); return v == null ? def : JSON.parse(v); } catch (e) { return def; } };

  window.CC = { sb, $, $$, esc, pesos, cant, fecha, fechaCorta, limpiarBusqueda, toast, rpc, consulta, conBoton, exigirSesion, debounce, guardar, leer, mensajeError };
})();
