// Congelados Claudio · Administración: listas de precios y asignación a clientes
(async () => {
  const { sb, $, $$, esc, pesos, toast, rpc, consulta, conBoton, exigirSesion, debounce, leer, guardar } = CC;

  const ses = await exigirSesion();
  if (!ses) return;
  if (ses.perfil.rol !== 'admin') { location.replace('app.html'); return; }
  $('#usuario').textContent = `${ses.perfil.nombre || ses.perfil.email} · admin`;
  $('#btn-salir').addEventListener('click', async () => { await sb.auth.signOut(); location.replace('index.html'); });

  const BASE = '__base__';               // pseudo-lista: precio base de los productos
  const E = { listas: [], camiones: [], clientes: [], especiales: {}, sel: null, precios: [], filtrados: [] };
  const plural = (n, uno, varios) => `${n} ${n === 1 ? uno : varios}`;
  const nombreLista = (id) => id === BASE ? 'Precio base' : (E.listas.find((l) => l.id === id)?.nombre || 'Sin lista (base)');

  // ---------- Diálogo ----------
  const dlg = $('#dlg');
  dlg.addEventListener('click', (e) => { if (e.target.closest('[data-cerrar]') || e.target === dlg) dlg.close(); });
  function dialogo(titulo, html, botones = []) {
    $('#dlg-titulo').textContent = titulo;
    $('#dlg-cuerpo').innerHTML = html;
    const pie = $('#dlg-pie');
    pie.innerHTML = '';
    botones.forEach((b) => {
      const el = document.createElement('button');
      el.className = 'btn ' + (b.clase || '');
      el.textContent = b.texto;
      el.addEventListener('click', () => conBoton(el, async () => { if ((await b.accion()) !== false) dlg.close(); }));
      pie.appendChild(el);
    });
    if (!dlg.open) dlg.showModal();
  }

  // ---------- Segmentos ----------
  function irA(seg) {
    $$('[data-seg]').forEach((b) => b.classList.toggle('activo', b.dataset.seg === seg));
    $('#seg-listas').hidden = seg !== 'listas';
    $('#seg-asignar').hidden = seg !== 'asignar';
    guardar('admin_seg', seg);
    if (seg === 'asignar') renderClientes();
  }
  $$('[data-seg]').forEach((b) => b.addEventListener('click', () => irA(b.dataset.seg)));

  // ---------- Carga de datos ----------
  async function cargarTodo() {
    const [listas, camiones, clientes, esp] = await Promise.all([
      consulta(sb.from('listas_precios').select('*').order('nombre')),
      consulta(sb.from('camiones').select('id, numero').order('numero')),
      consulta(sb.from('clientes').select('id, codigo, nombre, localidad, observaciones, lista_precio_id, camion_id, activo').order('nombre').limit(5000)),
      consulta(sb.from('listas_precios_items').select('lista_id').limit(20000)),
    ]);
    E.listas = listas; E.camiones = camiones; E.clientes = clientes;
    E.especiales = esp.reduce((m, r) => { m[r.lista_id] = (m[r.lista_id] || 0) + 1; return m; }, {});
    renderListas();
    llenarSelectsAsignar();
  }

  // ================= LISTAS =================
  function renderListas() {
    const porLista = E.clientes.reduce((m, c) => { const k = c.lista_precio_id || BASE; m[k] = (m[k] || 0) + 1; return m; }, {});
    const filas = [{ id: BASE, nombre: 'Precio base', ajuste_porcentaje: null, activo: true, descripcion: 'El precio de lista de cada producto' }, ...E.listas];
    $('#listas').innerHTML = filas.map((l) => `
      <li class="clic ${E.sel === l.id ? 'elegida' : ''}" data-id="${l.id}">
        <div class="fila entre">
          <span><b>${esc(l.nombre)}</b> ${l.activo ? '' : '<span class="etiqueta error">inactiva</span>'}</span>
          <span class="fuerte">${l.id === BASE ? '' : (Number(l.ajuste_porcentaje) > 0 ? '+' : '') + Number(l.ajuste_porcentaje).toLocaleString('es-AR') + ' %'}</span>
        </div>
        <div class="suave">${esc(l.descripcion || '')}${l.descripcion ? ' · ' : ''}${plural(porLista[l.id] || 0, 'cliente', 'clientes')}${l.id !== BASE && E.especiales[l.id] ? ` · ${plural(E.especiales[l.id], 'precio especial', 'precios especiales')}` : ''}</div>
      </li>`).join('');
  }
  $('#listas').addEventListener('click', (e) => { const li = e.target.closest('[data-id]'); if (li) elegirLista(li.dataset.id); });

  async function elegirLista(id) {
    E.sel = id;
    renderListas();
    const base = id === BASE;
    const l = E.listas.find((x) => x.id === id);
    $('#detalle-lista').hidden = false;
    $('#dl-titulo').textContent = base ? 'Precio base' : `Lista: ${l.nombre}`;
    $('#form-lista').hidden = base;
    $('#th-lista').textContent = base ? '' : 'Precio lista';
    if (!base) {
      $('#fl-nombre').value = l.nombre;
      $('#fl-ajuste').value = l.ajuste_porcentaje;
      $('#fl-desc').value = l.descripcion || '';
      $('#fl-activo').checked = l.activo;
    }
    $('#dl-ayuda').innerHTML = base
      ? 'Para actualizar precios: <b>Descargar planilla</b>, cambiá la columna <b>Precio</b> en Excel y usá <b>Subir planilla</b>. Solo cambian los productos cuyo precio sea distinto, y cada cambio queda en el historial.'
      : `Esta lista aplica <b>${Number(l.ajuste_porcentaje).toLocaleString('es-AR')} %</b> sobre el precio base. Si querés precios puntuales distintos, descargá la planilla, cambiá la columna <b>Precio lista</b> y subila: esos productos quedan con <b>precio especial</b> (marcados con ★).`;
    $('#dl-buscar').value = '';
    $('#dl-precios').innerHTML = '<tr><td colspan="4" class="vacio">Cargando…</td></tr>';
    try {
      E.precios = await rpc('precios_de_lista', { p_lista_id: base ? null : id });
      filtrarPrecios();
    } catch (err) { toast(err.message, 'error'); }
    $('#detalle-lista').scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  function filtrarPrecios() {
    const t = $('#dl-buscar').value.trim().toLowerCase();
    const base = E.sel === BASE;
    const rows = t ? E.precios.filter((p) => (p.codigo + ' ' + p.descripcion + ' ' + (p.marca || '')).toLowerCase().includes(t)) : E.precios;
    $('#dl-precios').innerHTML = rows.slice(0, 400).map((p) => `<tr>
      <td class="suave">${esc(p.codigo)}</td>
      <td>${esc(p.descripcion)}<div class="suave">${esc(p.marca || '')}</div></td>
      <td class="num ${Number(p.precio_base) === 0 ? 'deuda' : ''}">${Number(p.precio_base) === 0 ? 'sin precio' : pesos(p.precio_base)}</td>
      <td class="num fuerte">${base ? '' : (p.especial ? '★ ' : '') + pesos(p.precio_lista)}</td></tr>`).join('')
      || '<tr><td colspan="4" class="vacio">Sin productos</td></tr>';
    const sinPrecio = E.precios.filter((p) => Number(p.precio_base) === 0).length;
    $('#dl-pie').textContent = `${E.precios.length} productos activos${sinPrecio ? ` · ${sinPrecio} sin precio base (no se pueden vender)` : ''}${rows.length > 400 ? ' · mostrando 400, usá el filtro' : ''}`;
  }
  $('#dl-buscar').addEventListener('input', debounce(filtrarPrecios, 150));

  $('#form-lista').addEventListener('submit', (e) => {
    e.preventDefault();
    conBoton(e.submitter, async () => {
      const ajuste = Number($('#fl-ajuste').value || 0);
      if (ajuste <= -100) throw new Error('El ajuste tiene que ser mayor a -100 %');
      await consulta(sb.from('listas_precios').update({
        nombre: $('#fl-nombre').value.trim(), ajuste_porcentaje: ajuste,
        descripcion: $('#fl-desc').value.trim() || null, activo: $('#fl-activo').checked,
      }).eq('id', E.sel));
      toast('Lista guardada', 'ok');
      await cargarTodo();
      await elegirLista(E.sel);
    });
  });

  $('#btn-borrar-especiales').addEventListener('click', () => {
    const l = E.listas.find((x) => x.id === E.sel);
    const n = E.especiales[E.sel] || 0;
    if (!n) { toast('Esta lista no tiene precios especiales', 'info'); return; }
    dialogo('Quitar precios especiales', `<p>Se borran los <b>${n}</b> precios especiales de <b>${esc(l.nombre)}</b>. Esos productos vuelven a calcularse con el precio base ${Number(l.ajuste_porcentaje) ? 'y el ' + Number(l.ajuste_porcentaje).toLocaleString('es-AR') + ' % de la lista' : ''}.</p>`,
      [{ texto: 'Volver', clase: 'sec', accion: () => true },
        { texto: 'Quitar', clase: 'peligro', accion: async () => {
          await consulta(sb.from('listas_precios_items').delete().eq('lista_id', E.sel));
          toast('Precios especiales quitados', 'ok');
          await cargarTodo(); await elegirLista(E.sel);
        } }]);
  });

  $('#btn-nueva-lista').addEventListener('click', () => {
    dialogo('Nueva lista de precios', `
      <div class="campo"><label for="nl-nombre">Nombre *</label><input id="nl-nombre" placeholder="Ej.: Mayorista"></div>
      <div class="campo"><label for="nl-ajuste">Ajuste sobre el precio base (%)</label><input id="nl-ajuste" type="number" step="0.01" inputmode="decimal" value="0"></div>
      <p class="suave">-10 = 10 % más barato que el precio base · 5 = 5 % más caro · 0 = igual al precio base (útil si vas a subir precios especiales con una planilla).</p>
      <div class="campo"><label for="nl-desc">Descripción</label><input id="nl-desc"></div>`,
    [{ texto: 'Cancelar', clase: 'sec', accion: () => true },
      { texto: 'Crear', clase: 'ok', accion: async () => {
        const nombre = $('#nl-nombre').value.trim();
        if (!nombre) throw new Error('Poné un nombre');
        const ajuste = Number($('#nl-ajuste').value || 0);
        if (ajuste <= -100) throw new Error('El ajuste tiene que ser mayor a -100 %');
        const nueva = await consulta(sb.from('listas_precios').insert({ nombre, ajuste_porcentaje: ajuste, descripcion: $('#nl-desc').value.trim() || null }).select().single());
        toast(`Lista "${nombre}" creada`, 'ok');
        await cargarTodo();
        setTimeout(() => elegirLista(nueva.id), 0);
      } }]);
    setTimeout(() => $('#nl-nombre').focus(), 50);
  });

  // ---------- Descargar planilla ----------
  $('#btn-descargar').addEventListener('click', () => {
    const base = E.sel === BASE;
    const filas = E.precios.map((p) => base
      ? { 'Código': p.codigo, 'Producto': p.descripcion, 'Marca': p.marca || '', 'Rubro': p.rubro || '', 'Precio': Number(p.precio_base) }
      : { 'Código': p.codigo, 'Producto': p.descripcion, 'Marca': p.marca || '', 'Precio base': Number(p.precio_base), 'Precio lista': Number(p.precio_lista), 'Especial': p.especial ? 'sí' : '' });
    const hoja = XLSX.utils.json_to_sheet(filas);
    hoja['!cols'] = base ? [{ wch: 9 }, { wch: 46 }, { wch: 14 }, { wch: 28 }, { wch: 12 }] : [{ wch: 9 }, { wch: 46 }, { wch: 14 }, { wch: 12 }, { wch: 12 }, { wch: 8 }];
    const libro = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(libro, hoja, 'Precios');
    const nombre = base ? 'precio-base' : nombreLista(E.sel).toLowerCase().replace(/[^a-z0-9áéíóúñ]+/gi, '-');
    XLSX.writeFile(libro, `${nombre}-${new Date().toISOString().slice(0, 10)}.xlsx`);
  });

  // ---------- Subir planilla ----------
  // Convierte "$34.000,50", "34,000.50", "34000" o un número de Excel a número
  function aNumero(v) {
    if (typeof v === 'number') return v;
    let s = String(v ?? '').replace(/[^\d.,-]/g, '');
    if (!s) return null;
    const p = s.lastIndexOf('.'), c = s.lastIndexOf(',');
    if (p >= 0 && c >= 0) {                       // 34.000,50  o  34,000.50
      const dec = p > c ? '.' : ',';
      s = s.split(dec === '.' ? ',' : '.').join('').replace(dec, '.');
    } else if (c >= 0) {                          // 34000,5  o  34,000
      s = (s.split(',').length > 2 || /,\d{3}$/.test(s)) ? s.replace(/,/g, '') : s.replace(',', '.');
    } else if (p >= 0 && (s.split('.').length > 2 || /^\d{1,3}\.\d{3}$/.test(s))) {
      s = s.replace(/\./g, '');                  // 34.000  o  1.234.000
    }
    const n = Number(s);
    return Number.isFinite(n) ? n : null;
  }

  function leerFilas(matriz) {
    const base = E.sel === BASE;
    const norm = (x) => String(x ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim();
    let fila = -1, cCod = -1, cPre = -1;
    for (let i = 0; i < Math.min(matriz.length, 15) && fila < 0; i++) {
      const h = (matriz[i] || []).map(norm);
      const cod = h.findIndex((x) => /^cod/.test(x) || x === 'sku');
      const precios = h.map((x, j) => (/precio|costo|importe/.test(x) ? j : -1)).filter((j) => j >= 0);
      if (cod >= 0 && precios.length) {
        fila = i; cCod = cod;
        const pref = precios.find((j) => (base ? /base|^precio$/ : /lista|especial/).test(h[j]));
        cPre = pref ?? precios.at(-1);
      }
    }
    if (fila < 0) throw new Error('No encontré las columnas. La planilla necesita una columna "Código" y una "Precio" (descargá la planilla de ejemplo).');
    return matriz.slice(fila + 1)
      .map((r) => ({ codigo: String(r[cCod] ?? '').trim().toUpperCase(), precio: aNumero(r[cPre]) }))
      .filter((r) => r.codigo);
  }

  // CSV propio: respeta el formato argentino ("$85.500,00") y los acentos, sin que la librería adivine números
  async function leerCsv(archivo) {
    const bytes = new Uint8Array(await archivo.arrayBuffer());
    let texto = new TextDecoder('utf-8').decode(bytes);
    if (texto.includes('\uFFFD')) texto = new TextDecoder('windows-1252').decode(bytes);  // CSV guardado por Excel en Windows
    texto = texto.replace(/^\uFEFF/, '');
    const primera = texto.split(/\r?\n/)[0] || '';
    const sep = [';', '\t', ','].sort((a, b) => primera.split(b).length - primera.split(a).length)[0];
    const filas = [];
    let fila = [], campo = '', comillas = false;
    for (let i = 0; i < texto.length; i++) {
      const ch = texto[i];
      if (comillas) {
        if (ch === '"' && texto[i + 1] === '"') { campo += '"'; i++; }
        else if (ch === '"') comillas = false;
        else campo += ch;
      } else if (ch === '"') comillas = true;
      else if (ch === sep) { fila.push(campo); campo = ''; }
      else if (ch === '\n' || ch === '\r') {
        if (ch === '\r' && texto[i + 1] === '\n') i++;
        fila.push(campo); filas.push(fila); fila = []; campo = '';
      } else campo += ch;
    }
    if (campo || fila.length) { fila.push(campo); filas.push(fila); }
    return filas;
  }

  $('#archivo').addEventListener('change', async (e) => {
    const f = e.target.files[0];
    e.target.value = '';
    if (!f) return;
    try {
      let matriz;
      if (/\.(csv|txt)$/i.test(f.name)) matriz = await leerCsv(f);
      else {
        const libro = XLSX.read(await f.arrayBuffer(), { type: 'array' });
        matriz = XLSX.utils.sheet_to_json(libro.Sheets[libro.SheetNames[0]], { header: 1, raw: true, defval: '' });
      }
      const filas = leerFilas(matriz);
      if (!filas.length) throw new Error('La planilla no tiene filas con código');
      previsualizar(f.name, filas);
    } catch (err) { toast(err.message, 'error', 7000); }
  });

  function previsualizar(archivo, filas) {
    const base = E.sel === BASE;
    const actual = Object.fromEntries(E.precios.map((p) => [p.codigo.toUpperCase(), p]));
    const malas = filas.filter((r) => r.precio == null || r.precio < 0);
    const validas = filas.filter((r) => r.precio != null && r.precio >= 0);
    const noEnc = validas.filter((r) => !actual[r.codigo]);
    const cambian = validas.filter((r) => {
      const p = actual[r.codigo];
      return p && Math.round(r.precio * 100) !== Math.round(Number(base ? p.precio_base : p.precio_lista) * 100);
    });
    const destino = base ? '<b>precio base</b> de los productos' : `precio especial de la lista <b>${esc(nombreLista(E.sel))}</b>`;
    dialogo('Revisar antes de aplicar', `
      <p class="suave">${esc(archivo)} · ${filas.length} filas leídas</p>
      <p>Se va a actualizar el ${destino}.</p>
      <table>
        <tr><td>Precios que cambian</td><td class="num fuerte">${cambian.length}</td></tr>
        <tr><td>Iguales a los actuales</td><td class="num">${validas.length - noEnc.length - cambian.length}</td></tr>
        <tr><td>Códigos que no existen</td><td class="num ${noEnc.length ? 'deuda' : ''}">${noEnc.length}</td></tr>
        <tr><td>Precio vacío o inválido</td><td class="num ${malas.length ? 'deuda' : ''}">${malas.length}</td></tr>
      </table>
      ${noEnc.length ? `<p class="suave">No existen: ${esc(noEnc.slice(0, 15).map((r) => r.codigo).join(', '))}${noEnc.length > 15 ? '…' : ''}</p>` : ''}
      ${malas.length ? `<p class="suave">Sin precio válido: ${esc(malas.slice(0, 15).map((r) => r.codigo).join(', '))}${malas.length > 15 ? '…' : ''}</p>` : ''}
      ${cambian.length ? `<h3 style="margin-top:12px">Ejemplos</h3><table><thead><tr><th>Producto</th><th class="num">Antes</th><th class="num">Ahora</th></tr></thead><tbody>
        ${cambian.slice(0, 8).map((r) => { const p = actual[r.codigo]; return `<tr><td>${esc(p.descripcion)}</td><td class="num suave">${pesos(base ? p.precio_base : p.precio_lista)}</td><td class="num fuerte">${pesos(r.precio)}</td></tr>`; }).join('')}
      </tbody></table>` : ''}
      <div class="campo" style="margin-top:12px"><label for="imp-motivo">Motivo (queda en el historial)</label><input id="imp-motivo" placeholder="Ej.: aumento McCain octubre"></div>`,
    [{ texto: 'Cancelar', clase: 'sec', accion: () => true },
      ...(cambian.length ? [{ texto: `Aplicar ${cambian.length} precios`, clase: 'ok', accion: async () => {
        const r = await rpc('importar_precios', {
          p_items: cambian.map((x) => ({ codigo: x.codigo, precio: x.precio })),
          p_lista_id: base ? null : E.sel,
          p_motivo: $('#imp-motivo').value.trim() || `Planilla ${archivo}`,
        });
        toast(`${r.actualizados} precios actualizados`, 'ok', 5000);
        await cargarTodo(); await elegirLista(E.sel);
      } }] : [])]);
  }

  // ================= ASIGNAR =================
  const opcionesListas = (conTodas) => (conTodas ? '<option value="*">Todas las listas</option>' : '') +
    `<option value="${BASE}">${conTodas ? 'Sin lista (precio base)' : 'Precio base (sin lista)'}</option>` +
    E.listas.map((l) => `<option value="${l.id}">${esc(l.nombre)}${l.activo ? '' : ' (inactiva)'}</option>`).join('');
  const opcionesCamiones = (conTodos) => (conTodos ? '<option value="*">Todos los camiones</option>' : '') +
    `<option value="${BASE}">Sin camión</option>` + E.camiones.map((c) => `<option value="${c.id}">${esc(c.numero)}</option>`).join('');

  function llenarSelectsAsignar() {
    const mantener = (sel, html) => { const v = sel.value; sel.innerHTML = html; if ([...sel.options].some((o) => o.value === v)) sel.value = v; };
    mantener($('#as-f-lista'), opcionesListas(true));
    mantener($('#as-f-camion'), opcionesCamiones(true));
    const obs = [...new Set(E.clientes.map((c) => c.observaciones).filter(Boolean))].sort();
    mantener($('#as-f-obs'), '<option value="*">Todas las observaciones</option>' + obs.map((o) => `<option value="${esc(o)}">${esc(o)}</option>`).join(''));
    mantener($('#as-lista-dest'), opcionesListas(false));
    mantener($('#as-camion-dest'), opcionesCamiones(false));
    if (!$('#seg-asignar').hidden) renderClientes();
  }

  const elegidos = new Set();
  let visibles = [];
  function renderClientes() {
    const t = $('#as-buscar').value.trim().toLowerCase();
    const fl = $('#as-f-lista').value, fc = $('#as-f-camion').value, fo = $('#as-f-obs').value;
    visibles = E.clientes.filter((c) =>
      (!t || (c.nombre + ' ' + c.codigo + ' ' + (c.localidad || '')).toLowerCase().includes(t)) &&
      (fl === '*' || (c.lista_precio_id || BASE) === fl) &&
      (fc === '*' || (c.camion_id || BASE) === fc) &&
      (fo === '*' || c.observaciones === fo));
    const camion = (id) => E.camiones.find((x) => x.id === id)?.numero || '—';
    $('#as-clientes').innerHTML = visibles.map((c) => `<tr>
      <td><input type="checkbox" data-sel="${c.id}" ${elegidos.has(c.id) ? 'checked' : ''} aria-label="Elegir ${esc(c.nombre)}" style="width:auto;min-height:0"></td>
      <td><b>${esc(c.nombre)}</b> <span class="suave">#${c.codigo}</span>${c.activo ? '' : ' <span class="etiqueta error">inactivo</span>'}<div class="suave">${esc([c.localidad, c.observaciones].filter(Boolean).join(' · '))}</div></td>
      <td><select data-lista="${c.id}" aria-label="Lista de ${esc(c.nombre)}" style="min-height:36px;padding:4px 6px">${opcionesListas(false)}</select></td>
      <td>${esc(camion(c.camion_id))}</td></tr>`).join('') || '<tr><td colspan="4" class="vacio">Sin clientes con esos filtros</td></tr>';
    visibles.forEach((c) => { const s = $(`[data-lista="${c.id}"]`); if (s) s.value = c.lista_precio_id || BASE; });
    $('#as-todos').checked = visibles.length > 0 && visibles.every((c) => elegidos.has(c.id));
    $('#as-pie').textContent = `${visibles.length} de ${E.clientes.length} clientes`;
    $('#as-contador').textContent = `${elegidos.size} seleccionado${elegidos.size === 1 ? '' : 's'}`;
  }
  $('#as-buscar').addEventListener('input', debounce(renderClientes, 150));
  ['#as-f-lista', '#as-f-camion', '#as-f-obs'].forEach((s) => $(s).addEventListener('change', renderClientes));

  $('#as-clientes').addEventListener('change', async (e) => {
    const chk = e.target.dataset.sel;
    if (chk) { e.target.checked ? elegidos.add(chk) : elegidos.delete(chk); renderClientes(); return; }
    const id = e.target.dataset.lista;
    if (!id) return;
    const valor = e.target.value === BASE ? null : e.target.value;
    try {
      await consulta(sb.from('clientes').update({ lista_precio_id: valor }).eq('id', id));
      E.clientes.find((c) => c.id === id).lista_precio_id = valor;
      toast(`Lista cambiada a ${nombreLista(valor || BASE)}`, 'ok');
      renderListas();
    } catch (err) { toast(err.message, 'error'); renderClientes(); }
  });
  $('#as-todos').addEventListener('change', (e) => {
    visibles.forEach((c) => (e.target.checked ? elegidos.add(c.id) : elegidos.delete(c.id)));
    renderClientes();
  });

  async function asignarEnBloque(boton, campo, valor, texto) {
    await conBoton(boton, async () => {
      const ids = [...elegidos];
      if (!ids.length) throw new Error('Tildá al menos un cliente');
      await consulta(sb.from('clientes').update({ [campo]: valor === BASE ? null : valor }).in('id', ids));
      E.clientes.forEach((c) => { if (elegidos.has(c.id)) c[campo] = valor === BASE ? null : valor; });
      toast(`${texto} asignado a ${ids.length} cliente${ids.length === 1 ? '' : 's'}`, 'ok');
      elegidos.clear();
      renderClientes(); renderListas();
    });
  }
  $('#btn-asignar-lista').addEventListener('click', (e) => {
    const v = $('#as-lista-dest').value;
    asignarEnBloque(e.currentTarget, 'lista_precio_id', v, `"${nombreLista(v)}"`);
  });
  $('#btn-asignar-camion').addEventListener('click', (e) => {
    const v = $('#as-camion-dest').value;
    asignarEnBloque(e.currentTarget, 'camion_id', v, v === BASE ? 'Sin camión' : `Camión ${E.camiones.find((c) => c.id === v)?.numero}`);
  });

  // ---------- Inicio ----------
  try { await cargarTodo(); } catch (err) { toast(err.message, 'error', 8000); }
  irA(leer('admin_seg') || 'listas');
})();
