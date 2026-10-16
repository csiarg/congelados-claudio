// Congelados Claudio · panel del operario
(async () => {
  const { sb, $, $$, esc, pesos, cant, fecha, fechaCorta, limpiarBusqueda, toast, rpc, consulta, conBoton, exigirSesion, debounce, guardar, leer } = CC;

  const ses = await exigirSesion();
  if (!ses) return;

  const E = {
    perfil: ses.perfil,
    puedeOperar: ['admin', 'operario'].includes(ses.perfil.rol),
    camiones: [],
    camionId: null,
    recorrido: null,
    listas: [],
    venta: { cliente: null, carrito: [], pagoEditado: false },
    cobro: { cliente: null },
    carga: [],
  };
  const camionActual = () => E.camiones.find((c) => c.id === E.camionId);
  const pasoCant = (unidad) => (unidad === 'kg' ? '0.1' : '1');

  // ================= Cabecera, camión y permisos =================
  $('#usuario').textContent = `${E.perfil.nombre || E.perfil.email} · ${E.perfil.rol}`;
  if (!E.puedeOperar) {
    $$('.solo-operar').forEach((el) => { el.hidden = true; });
    $('#aviso-consulta').hidden = false;
    $('[data-ir="vender"]').hidden = true;
  }

  $('#btn-salir').addEventListener('click', async () => {
    await sb.auth.signOut();
    location.replace('index.html');
  });

  try {
    [E.camiones, E.listas] = await Promise.all([
      consulta(sb.from('camiones').select('id, numero, chofer_nombre').eq('activo', true).order('numero')),
      consulta(sb.from('listas_precios').select('id, nombre, ajuste_porcentaje').eq('activo', true).order('nombre')),
    ]);
  } catch (e) { toast(e.message, 'error', 8000); }

  const guardado = leer('camion');
  E.camionId = [guardado, E.perfil.camion_id].find((id) => id && E.camiones.some((c) => c.id === id)) || null;
  $('#sel-camion').innerHTML = '<option value="">Sin camión (depósito)</option>' +
    E.camiones.map((c) => `<option value="${c.id}">🚚 ${esc(c.numero)}${c.chofer_nombre ? ' · ' + esc(c.chofer_nombre) : ''}</option>`).join('');
  $('#sel-camion').value = E.camionId || '';
  $('#sel-camion').addEventListener('change', async (e) => {
    E.camionId = e.target.value || null;
    guardar('camion', E.camionId);
    ajustarOrigenVenta();
    await refrescarRecorrido();
    if (!$('#tab-camion').hidden) cargarStockCamion();
    if (!$('#tab-pedidos').hidden) cargarPedidos();
  });

  async function refrescarRecorrido() {
    const barra = $('#barra-recorrido');
    if (!E.camionId) { E.recorrido = null; barra.hidden = true; return; }
    try {
      E.recorrido = await consulta(sb.from('recorridos').select('id, numero, abierto_at')
        .eq('camion_id', E.camionId).eq('estado', 'en_curso').maybeSingle());
    } catch (e) { E.recorrido = null; }
    barra.hidden = false;
    barra.innerHTML = E.recorrido
      ? `<span>🟢 Recorrido #${E.recorrido.numero} abierto · desde ${esc(fecha(E.recorrido.abierto_at))}</span>`
      : '<span>⚪ Sin recorrido abierto · se abre solo al cargar el camión o vender</span>';
  }

  // ================= Navegación =================
  function irA(tab) {
    $$('[data-tab]').forEach((s) => { s.hidden = s.id !== 'tab-' + tab; });
    $$('.nav-inferior button').forEach((b) => b.classList.toggle('activo', b.dataset.ir === tab));
    guardar('tab', tab);
    window.scrollTo(0, 0);
    if (tab === 'camion') cargarStockCamion();
    if (tab === 'pedidos') cargarPedidos();
    if (tab === 'clientes') cargarClientes();
  }
  $$('.nav-inferior button').forEach((b) => b.addEventListener('click', () => irA(b.dataset.ir)));

  // ================= Diálogo genérico =================
  const dlg = $('#dlg');
  dlg.addEventListener('click', (e) => { if (e.target.closest('[data-cerrar]') || e.target === dlg) dlg.close(); });
  function dialogo(titulo, html, botones = []) {
    $('#dlg-titulo').textContent = titulo;
    $('#dlg-cuerpo').innerHTML = html;
    const pie = $('#dlg-pie');
    pie.innerHTML = '';
    botones.forEach((b) => {
      const el = document.createElement(b.href ? 'a' : 'button');
      el.className = 'btn ' + (b.clase || '');
      el.textContent = b.texto;
      if (b.href) { el.href = b.href; el.target = '_blank'; el.rel = 'noopener'; }
      if (b.accion) el.addEventListener('click', () => conBoton(el, async () => { if ((await b.accion()) !== false) dlg.close(); }));
      pie.appendChild(el);
    });
    pie.hidden = botones.length === 0;
    if (!dlg.open) dlg.showModal();
  }
  const confirmar = (titulo, html, textoSi, accion, clase = 'ok') =>
    dialogo(titulo, html, [{ texto: 'Volver', clase: 'sec', accion: () => true }, { texto: textoSi, clase, accion }]);

  // ================= Buscadores reutilizables =================
  function cerrarAlSalir(input, caja) {
    document.addEventListener('click', (e) => { if (!caja.contains(e.target) && e.target !== input) caja.hidden = true; });
    input.addEventListener('keydown', (e) => { if (e.key === 'Escape') caja.hidden = true; });
  }

  async function buscarClientes(texto) {
    const t = limpiarBusqueda(texto);
    if (!t) return [];
    let q = sb.from('v_saldos').select('*').eq('activo', true).order('nombre').limit(15);
    q = /^\d+$/.test(t) ? q.or(`codigo.eq.${t},nombre.ilike.*${t}*,telefono.ilike.*${t}*`) : q.ilike('nombre', `%${t}%`);
    return consulta(q);
  }

  function buscadorClientes(input, caja, alElegir) {
    let res = [];
    input.addEventListener('input', debounce(async () => {
      try { res = await buscarClientes(input.value); } catch (e) { toast(e.message, 'error'); return; }
      caja.innerHTML = res.length
        ? res.map((c, i) => `<button type="button" data-i="${i}"><b>${esc(c.nombre)}</b> <span class="suave">#${c.codigo}${c.localidad ? ' · ' + esc(c.localidad) : ''}</span>
            ${Number(c.saldo) > 0 ? `<span class="deuda" style="float:right">${pesos(c.saldo)}</span>` : ''}</button>`).join('')
        : '<div class="vacio">Sin resultados</div>';
      caja.hidden = !input.value.trim();
    }));
    caja.addEventListener('click', (e) => {
      const b = e.target.closest('[data-i]');
      if (!b) return;
      caja.hidden = true;
      input.value = '';
      alElegir(res[Number(b.dataset.i)]);
    });
    cerrarAlSalir(input, caja);
  }

  function buscadorProductos(input, caja, opciones, alElegir) {
    let res = [];
    input.addEventListener('input', debounce(async () => {
      const t = input.value.trim();
      if (!t) { caja.hidden = true; return; }
      try {
        res = await rpc('buscar_productos', { p_termino: t, p_lista_id: opciones.lista(), p_camion_id: E.camionId, p_limite: 20 });
      } catch (e) { toast(e.message, 'error'); return; }
      const deCamion = opciones.desdeCamion();
      caja.innerHTML = res.length
        ? res.map((p, i) => {
          const stock = deCamion ? p.stock_camion : p.stock_deposito;
          return `<button type="button" data-i="${i}">
            <div class="fila entre"><span><b>${esc(p.descripcion)}</b> <span class="suave">${esc(p.codigo)}</span></span>
            ${opciones.mostrarPrecio ? `<span class="fuerte">${pesos(p.precio)}</span>` : ''}</div>
            <span class="suave">${deCamion ? 'En camión' : 'En depósito'}: <b class="${stock > 0 ? '' : 'deuda'}">${cant(stock)} ${esc(p.unidad)}</b></span>
          </button>`;
        }).join('')
        : '<div class="vacio">Sin resultados</div>';
      caja.hidden = false;
    }));
    caja.addEventListener('click', (e) => {
      const b = e.target.closest('[data-i]');
      if (!b) return;
      caja.hidden = true;
      input.value = '';
      alElegir(res[Number(b.dataset.i)]);
      input.focus();
    });
    cerrarAlSalir(input, caja);
  }

  const tarjetaCliente = (c) => `
    <div class="fila entre">
      <div>
        <div class="fuerte">${esc(c.nombre)} <span class="suave">#${c.codigo}</span></div>
        <div class="suave">${esc([c.localidad, c.lista_precio || 'Lista base', c.condicion_pago === 'cta_cte' ? 'Cuenta corriente' : 'Contado'].filter(Boolean).join(' · '))}</div>
      </div>
      <div class="num">
        <div class="suave">Saldo</div>
        <div class="${Number(c.saldo) > 0 ? 'deuda' : 'a-favor'}">${pesos(c.saldo)}</div>
      </div>
    </div>
    <button class="enlace" data-cambiar>Cambiar cliente</button>`;

  const linkWhatsapp = (num, texto) => num ? `https://wa.me/${encodeURIComponent(num)}?text=${encodeURIComponent(texto)}` : null;

  // ================= VENDER =================
  buscadorClientes($('#venta-buscar-cliente'), $('#venta-clientes-res'), elegirClienteVenta);

  function elegirClienteVenta(c) {
    E.venta.cliente = c;
    E.venta.pagoEditado = false;
    $('#venta-cliente').innerHTML = tarjetaCliente(c);
    $('#venta-cliente').hidden = false;
    $('#venta-buscar-cliente-caja').hidden = true;
    $('#venta-productos-caja').hidden = false;
    ajustarOrigenVenta();
    renderCarrito();
    $('#venta-buscar-prod').focus();
  }
  $('#venta-cliente').addEventListener('click', (e) => {
    if (!e.target.closest('[data-cambiar]')) return;
    E.venta.cliente = null;
    $('#venta-cliente').hidden = true;
    $('#venta-buscar-cliente-caja').hidden = false;
    $('#venta-productos-caja').hidden = true;
    $('#venta-cierre').hidden = true;
    $('#venta-buscar-cliente').focus();
  });

  function ajustarOrigenVenta() {
    const sel = $('#venta-origen');
    sel.querySelector('[value="camion"]').disabled = !E.camionId;
    if (!E.camionId) sel.value = 'deposito';
    else if (!E.venta.carrito.length) sel.value = 'camion';
  }
  $('#venta-origen').addEventListener('change', renderCarrito);

  buscadorProductos($('#venta-buscar-prod'), $('#venta-prod-res'), {
    lista: () => E.venta.cliente?.lista_precio_id ?? listaIdCliente(),
    desdeCamion: () => $('#venta-origen').value === 'camion',
    mostrarPrecio: true,
  }, (p) => {
    const ya = E.venta.carrito.find((x) => x.id === p.id);
    if (ya) ya.cantidad = Number(ya.cantidad) + 1;
    else E.venta.carrito.push({ id: p.id, codigo: p.codigo, descripcion: p.descripcion, unidad: p.unidad, precio: Number(p.precio), cantidad: 1, stock_camion: Number(p.stock_camion), stock_deposito: Number(p.stock_deposito) });
    renderCarrito();
  });

  // v_saldos trae el nombre de la lista; buscamos su id
  function listaIdCliente() {
    const c = E.venta.cliente;
    if (!c || !c.lista_precio) return null;
    return E.listas.find((l) => l.nombre === c.lista_precio)?.id || null;
  }

  function totalVenta() {
    return E.venta.carrito.reduce((s, x) => s + Math.round(Number(x.cantidad || 0) * x.precio * 100) / 100, 0);
  }

  function renderCarrito() {
    const deCamion = $('#venta-origen').value === 'camion';
    const tb = $('#venta-carrito');
    tb.innerHTML = E.venta.carrito.map((x, i) => {
      const stock = deCamion ? x.stock_camion : x.stock_deposito;
      const falta = Number(x.cantidad) > stock;
      return `<li class="renglon">
        <div class="desc"><div class="fuerte">${esc(x.descripcion)}</div>
          <div class="suave">${pesos(x.precio)} / ${esc(x.unidad)}${falta ? ` · <span class="etiqueta error">hay ${cant(stock)}</span>` : ''}</div></div>
        <button class="btn-icono" data-quitar="${i}" aria-label="Quitar">✕</button>
        <div class="acciones">
          <div class="cantidad"><input type="number" min="0" step="${pasoCant(x.unidad)}" inputmode="decimal" value="${x.cantidad}" data-cant="${i}" aria-label="Cantidad"> <span class="suave">${esc(x.unidad)}</span></div>
          <span class="fuerte" data-imp>${pesos(Number(x.cantidad || 0) * x.precio)}</span>
        </div>
      </li>`;
    }).join('');
    $('#venta-carrito-vacio').hidden = E.venta.carrito.length > 0;
    $('#venta-cierre').hidden = E.venta.carrito.length === 0;
    actualizarTotales();
  }

  function actualizarTotales() {
    const total = totalVenta();
    $('#venta-total').textContent = pesos(total);
    const c = E.venta.cliente;
    if (c && !E.venta.pagoEditado) $('#venta-pago').value = c.condicion_pago === 'contado' ? total.toFixed(2) : '';
    const pago = Number($('#venta-pago').value) || 0;
    if (c) {
      const saldo = Number(c.saldo) + total - pago;
      $('#venta-saldo-final').innerHTML = `Saldo del cliente después de esta venta: <b class="${saldo > 0 ? 'deuda' : 'a-favor'}">${pesos(saldo)}</b>`;
    }
  }

  $('#venta-carrito').addEventListener('input', (e) => {
    const i = e.target.dataset.cant;
    if (i == null) return;
    E.venta.carrito[i].cantidad = e.target.value;
    const fila = e.target.closest('li');
    const x = E.venta.carrito[i];
    fila.querySelector('[data-imp]').textContent = pesos(Number(x.cantidad || 0) * x.precio);
    actualizarTotales();
  });
  $('#venta-carrito').addEventListener('change', (e) => { if (e.target.dataset.cant != null) renderCarrito(); });
  $('#venta-carrito').addEventListener('click', (e) => {
    const b = e.target.closest('[data-quitar]');
    if (!b) return;
    E.venta.carrito.splice(Number(b.dataset.quitar), 1);
    renderCarrito();
  });
  $('#venta-pago').addEventListener('input', () => { E.venta.pagoEditado = true; actualizarTotales(); });

  $('#btn-confirmar-venta').addEventListener('click', (ev) => conBoton(ev.currentTarget, async () => {
    const c = E.venta.cliente;
    const items = E.venta.carrito.filter((x) => Number(x.cantidad) > 0);
    if (!c) throw new Error('Elegí un cliente');
    if (!items.length) throw new Error('Agregá al menos un producto con cantidad');
    const deCamion = $('#venta-origen').value === 'camion';
    if (deCamion && !E.camionId) throw new Error('Elegí tu camión arriba, o vendé desde el depósito');
    const pago = Number($('#venta-pago').value) || 0;

    const r = await rpc('crear_pedido', {
      p_cliente_id: c.cliente_id,
      p_items: items.map((x) => ({ producto_id: x.id, cantidad: Number(x.cantidad) })),
      p_camion_id: deCamion ? E.camionId : null,
      p_origen: 'app',
      p_notas: $('#venta-notas').value.trim() || null,
      p_pago_monto: pago,
      p_pago_medio: $('#venta-medio').value,
    });

    const texto = [
      `*Congelados Claudio*`,
      `Pedido #${r.numero} · ${fechaCorta(new Date())}`,
      ...items.map((x) => `• ${cant(x.cantidad)} ${x.unidad} ${x.descripcion}: ${pesos(Number(x.cantidad) * x.precio)}`),
      `*Total: ${pesos(r.total)}*`,
      pago > 0 ? `Pagó: ${pesos(pago)} (${$('#venta-medio').value})` : null,
      `Saldo de su cuenta: ${pesos(r.saldo_cliente)}`,
      '¡Gracias!',
    ].filter(Boolean).join('\n');

    const wa = linkWhatsapp(c.whatsapp, texto);
    dialogo(`✅ Venta #${r.numero} registrada`, `
      <p class="total-grande">${pesos(r.total)}</p>
      <p>${esc(c.nombre)} · ${r.estado === 'entregado' ? 'Entregado' : 'Pendiente de entrega'}</p>
      <p>Saldo del cliente: <b class="${r.saldo_cliente > 0 ? 'deuda' : 'a-favor'}">${pesos(r.saldo_cliente)}</b></p>
      ${wa ? '' : '<p class="suave">El cliente no tiene WhatsApp cargado.</p>'}`,
      [
        ...(wa ? [{ texto: 'Enviar por WhatsApp', clase: 'ok', href: wa }] : []),
        { texto: 'Nueva venta', clase: 'sec', accion: () => true },
      ]);

    // Reiniciar
    E.venta.carrito = [];
    E.venta.pagoEditado = false;
    $('#venta-notas').value = '';
    $('#venta-pago').value = '';
    E.venta.cliente = null;
    $('#venta-cliente').hidden = true;
    $('#venta-buscar-cliente-caja').hidden = false;
    $('#venta-productos-caja').hidden = true;
    $('#venta-cierre').hidden = true;
    renderCarrito();
    refrescarRecorrido();
  }));

  // ================= CAMIÓN =================
  async function cargarStockCamion() {
    const c = camionActual();
    $('#camion-titulo').textContent = c ? `Stock en el camión ${c.numero}` : 'Stock en el camión';
    const tb = $('#camion-stock');
    if (!c) { tb.innerHTML = ''; $('#camion-vacio').hidden = false; $('#camion-vacio').textContent = 'Elegí un camión arriba.'; return; }
    try {
      const filas = await consulta(sb.from('v_stock_camiones').select('codigo, descripcion, unidad, cantidad').eq('camion_id', c.id).order('descripcion'));
      tb.innerHTML = filas.map((f) => `<tr><td>${esc(f.descripcion)} <span class="suave">${esc(f.codigo)}</span></td><td class="num fuerte">${cant(f.cantidad)} ${esc(f.unidad)}</td></tr>`).join('');
      $('#camion-vacio').hidden = filas.length > 0;
      $('#camion-vacio').textContent = 'El camión está vacío.';
    } catch (e) { toast(e.message, 'error'); }
  }
  $('#btn-refrescar-camion').addEventListener('click', cargarStockCamion);

  buscadorProductos($('#carga-buscar'), $('#carga-res'), {
    lista: () => null, desdeCamion: () => false, mostrarPrecio: false,
  }, (p) => {
    const ya = E.carga.find((x) => x.id === p.id);
    if (ya) ya.cantidad = Number(ya.cantidad) + 1;
    else E.carga.push({ id: p.id, descripcion: p.descripcion, unidad: p.unidad, deposito: Number(p.stock_deposito), cantidad: 1 });
    renderCarga();
  });

  function renderCarga() {
    $('#carga-lista').innerHTML = E.carga.map((x, i) => `<li class="renglon">
      <div class="desc"><div class="fuerte">${esc(x.descripcion)}</div><div class="suave">En depósito: ${cant(x.deposito)} ${esc(x.unidad)}</div></div>
      <button class="btn-icono" data-quitar="${i}" aria-label="Quitar">✕</button>
      <div class="acciones"><div class="cantidad"><input type="number" min="0" step="${pasoCant(x.unidad)}" inputmode="decimal" value="${x.cantidad}" data-cant="${i}" aria-label="Cantidad"> <span class="suave">${esc(x.unidad)}</span></div></div>
    </li>`).join('');
    $('#btn-cargar').hidden = E.carga.length === 0;
  }
  $('#carga-lista').addEventListener('input', (e) => { const i = e.target.dataset.cant; if (i != null) E.carga[i].cantidad = e.target.value; });
  $('#carga-lista').addEventListener('click', (e) => { const b = e.target.closest('[data-quitar]'); if (b) { E.carga.splice(Number(b.dataset.quitar), 1); renderCarga(); } });

  $('#btn-cargar').addEventListener('click', (ev) => conBoton(ev.currentTarget, async () => {
    if (!E.camionId) throw new Error('Elegí el camión arriba');
    const items = E.carga.filter((x) => Number(x.cantidad) > 0).map((x) => ({ producto_id: x.id, cantidad: Number(x.cantidad) }));
    if (!items.length) throw new Error('No hay cantidades para cargar');
    await rpc('cargar_camion', { p_camion_id: E.camionId, p_items: items });
    toast(`Cargado al camión ${camionActual().numero}`, 'ok');
    E.carga = [];
    renderCarga();
    await Promise.all([cargarStockCamion(), refrescarRecorrido()]);
  }));

  $('#btn-cerrar-recorrido').addEventListener('click', () => {
    const c = camionActual();
    if (!c) { toast('Elegí el camión arriba', 'error'); return; }
    if (!E.recorrido) { toast('Este camión no tiene un recorrido abierto', 'error'); return; }
    confirmar(`Cerrar recorrido del ${c.numero}`,
      '<p>Todo lo que quedó en el camión vuelve al depósito y se cierra el día. ¿Seguimos?</p>',
      'Cerrar recorrido', async () => {
        const r = await rpc('cerrar_recorrido', { p_camion_id: c.id });
        await Promise.all([cargarStockCamion(), refrescarRecorrido()]);
        setTimeout(() => mostrarResumen(c, r), 0);
      }, 'peligro');
  });

  function mostrarResumen(c, r) {
    const cobr = Object.entries(r.cobranzas || {});
    dialogo(`Resumen del día · ${c.numero}`, `
      <div class="grilla-2" style="margin-bottom:12px">
        <div><div class="suave">Ventas (${r.pedidos})</div><div class="total-grande">${pesos(r.total_ventas)}</div></div>
        <div><div class="suave">Devoluciones</div><div class="fuerte">${pesos(r.total_devoluciones)}</div></div>
      </div>
      <h3>Cobranzas</h3>
      <table>${cobr.length ? cobr.map(([m, v]) => `<tr><td>${esc(m)}</td><td class="num">${pesos(v)}</td></tr>`).join('') : '<tr><td class="suave">Sin cobranzas</td></tr>'}</table>
      <h3 style="margin-top:14px">Mercadería</h3>
      <table>
        <thead><tr><th>Producto</th><th class="num">Cargó</th><th class="num">Vendió</th><th class="num">Dev.</th><th class="num">Bajó</th></tr></thead>
        <tbody>${(r.productos || []).map((p) => `<tr><td>${esc(p.descripcion)}</td><td class="num">${cant(p.cargado)}</td><td class="num">${cant(p.vendido)}</td><td class="num">${cant(p.devuelto)}</td><td class="num">${cant(p.descargado)}</td></tr>`).join('')}</tbody>
      </table>`, [{ texto: 'Listo', accion: () => true }]);
  }

  // ================= COBRAR =================
  buscadorClientes($('#cobro-buscar-cliente'), $('#cobro-clientes-res'), elegirClienteCobro);

  async function elegirClienteCobro(c) {
    E.cobro.cliente = c;
    $('#cobro-cliente').innerHTML = tarjetaCliente(c);
    $('#cobro-cliente').hidden = false;
    $('#cobro-buscar-cliente').closest('.buscador').hidden = true;
    $('#cobro-form').hidden = !E.puedeOperar;
    $('#cobro-monto').value = Number(c.saldo) > 0 ? Number(c.saldo).toFixed(2) : '';
    $('#cobro-ref').value = '';
    await cargarMovimientos(c.cliente_id);
  }
  $('#cobro-cliente').addEventListener('click', (e) => {
    if (!e.target.closest('[data-cambiar]')) return;
    E.cobro.cliente = null;
    $('#cobro-cliente').hidden = true;
    $('#cobro-form').hidden = true;
    $('#cobro-movs-caja').hidden = true;
    $('#cobro-buscar-cliente').closest('.buscador').hidden = false;
    $('#cobro-buscar-cliente').focus();
  });

  async function cargarMovimientos(clienteId) {
    try {
      const movs = await consulta(sb.from('v_cta_cte').select('fecha, descripcion, debe, haber, saldo')
        .eq('cliente_id', clienteId).order('fecha', { ascending: false }).order('id', { ascending: false }).limit(15));
      $('#cobro-movs').innerHTML = movs.map((m) => `<tr>
        <td>${esc(m.descripcion)}<div class="suave">${esc(fechaCorta(m.fecha))}</div></td>
        <td class="num ${Number(m.debe) > 0 ? 'deuda' : 'a-favor'}">${Number(m.debe) > 0 ? pesos(m.debe) : '−' + pesos(m.haber)}</td>
        <td class="num">${pesos(m.saldo)}</td></tr>`).join('') || '<tr><td colspan="3" class="vacio">Sin movimientos</td></tr>';
      $('#cobro-movs-caja').hidden = false;
    } catch (e) { toast(e.message, 'error'); }
  }

  $('#btn-cobrar').addEventListener('click', (ev) => conBoton(ev.currentTarget, async () => {
    const c = E.cobro.cliente;
    const monto = Number($('#cobro-monto').value);
    if (!c) throw new Error('Elegí un cliente');
    if (!(monto > 0)) throw new Error('Ingresá el monto cobrado');
    const r = await rpc('registrar_pago', {
      p_cliente_id: c.cliente_id, p_monto: monto, p_medio: $('#cobro-medio').value,
      p_referencia: $('#cobro-ref').value.trim() || null, p_camion_id: E.camionId,
    });
    toast(`Pago registrado. Nuevo saldo: ${pesos(r.saldo)}`, 'ok', 5000);
    const [act] = await consulta(sb.from('v_saldos').select('*').eq('cliente_id', c.cliente_id));
    await elegirClienteCobro(act);
  }));

  // ================= PEDIDOS =================
  $('#pedidos-filtro').addEventListener('change', cargarPedidos);

  function inicioDia(diasAtras = 0) {
    const d = new Date();
    d.setHours(0, 0, 0, 0);
    d.setDate(d.getDate() - diasAtras);
    return d.toISOString();
  }

  async function cargarPedidos() {
    const filtro = $('#pedidos-filtro').value;
    let q = sb.from('v_pedidos').select('*').order('fecha', { ascending: false }).limit(100);
    if (filtro === 'pendientes') {
      const c = camionActual();
      q = q.eq('estado', 'pendiente');
      if (c) q = q.eq('camion_reparto', c.numero);
    } else if (filtro === 'pendientes_todos') q = q.eq('estado', 'pendiente');
    else if (filtro === 'hoy') q = q.gte('fecha', inicioDia());
    else q = q.gte('fecha', inicioDia(6));
    try {
      const filas = await consulta(q);
      $('#pedidos-lista').innerHTML = filas.map((p) => `
        <li class="clic" data-id="${p.id}">
          <div class="fila entre">
            <span><b>#${p.numero}</b> ${esc(p.cliente)}</span>
            <span class="fuerte">${pesos(p.total)}</span>
          </div>
          <div class="fila entre suave">
            <span>${esc(fecha(p.fecha))}${p.direccion ? ' · ' + esc(p.direccion) : ''}</span>
            <span>${p.origen === 'whatsapp' ? '<span class="etiqueta ok">WhatsApp</span> ' : ''}${etiquetaEstado(p.estado)}</span>
          </div>
        </li>`).join('') || '<li class="vacio">No hay pedidos.</li>';
    } catch (e) { toast(e.message, 'error'); }
  }

  const etiquetaEstado = (e) => ({
    pendiente: '<span class="etiqueta aviso">Pendiente</span>',
    entregado: '<span class="etiqueta ok">Entregado</span>',
    cancelado: '<span class="etiqueta error">Cancelado</span>',
  }[e] || esc(e));

  $('#pedidos-lista').addEventListener('click', (e) => {
    const li = e.target.closest('[data-id]');
    if (li) abrirPedido(li.dataset.id);
  });

  async function abrirPedido(id) {
    let p, items, cli;
    try {
      [[p], items] = await Promise.all([
        consulta(sb.from('v_pedidos').select('*').eq('id', id)),
        consulta(sb.from('v_pedidos_items').select('*').eq('pedido_id', id).order('id')),
      ]);
      [cli] = await consulta(sb.from('clientes').select('whatsapp, telefono').eq('id', p.cliente_id));
    } catch (e) { toast(e.message, 'error'); return; }

    const html = `
      <p><b>${esc(p.cliente)}</b> ${etiquetaEstado(p.estado)}<br>
        <span class="suave">${esc([p.direccion, p.localidad].filter(Boolean).join(', '))}${cli?.telefono ? ' · ☎ ' + esc(cli.telefono) : ''}</span></p>
      <p class="suave">${esc(fecha(p.fecha))} · ${esc(p.origen)}${p.camion ? ' · camión ' + esc(p.camion) : ''}${p.camion_reparto && !p.camion ? ' · reparto ' + esc(p.camion_reparto) : ''}</p>
      ${p.notas ? `<div class="aviso-caja info">📝 ${esc(p.notas)}</div>` : ''}
      <table>
        <thead><tr><th>Producto</th><th class="num">Cant.</th><th class="num">Importe</th></tr></thead>
        <tbody>${items.map((i) => `<tr><td>${esc(i.descripcion)}<div class="suave">${pesos(i.precio_unitario)} / ${esc(i.unidad)}</div>${Number(i.cantidad_devuelta) > 0 ? `<span class="etiqueta aviso">devuelto ${cant(i.cantidad_devuelta)}</span>` : ''}</td>
          <td class="num">${cant(i.cantidad)} ${esc(i.unidad)}</td><td class="num">${pesos(i.importe)}</td></tr>`).join('')}</tbody>
      </table>
      <p class="fila entre" style="margin-top:10px"><span>Total</span><span class="total-grande">${pesos(p.total)}</span></p>
      ${Number(p.devuelto) > 0 ? `<p class="suave">Devuelto: ${pesos(p.devuelto)}</p>` : ''}`;

    const botones = [];
    if (E.puedeOperar && p.estado === 'pendiente') {
      botones.push({ texto: 'Cancelar', clase: 'peligro', accion: () => { pedirCancelacion(p); return false; } });
      botones.push({ texto: 'Marcar entregado', clase: 'ok', accion: async () => {
        await rpc('marcar_entregado', { p_pedido_id: p.id });
        toast(`Pedido #${p.numero} entregado`, 'ok');
        cargarPedidos();
      } });
    }
    if (E.puedeOperar && p.estado !== 'cancelado') {
      botones.unshift({ texto: 'Devolución', clase: 'sec', accion: () => { pedirDevolucion(p, items); return false; } });
    }
    const wa = linkWhatsapp(cli?.whatsapp, `*Congelados Claudio*\nPedido #${p.numero}\n` +
      items.map((i) => `• ${cant(i.cantidad)} ${i.unidad} ${i.descripcion}: ${pesos(i.importe)}`).join('\n') + `\n*Total: ${pesos(p.total)}*`);
    if (wa) botones.unshift({ texto: 'WhatsApp', clase: 'sec', href: wa });
    dialogo(`Pedido #${p.numero}`, html, botones);
  }

  function pedirCancelacion(p) {
    dialogo(`Cancelar pedido #${p.numero}`, `
      <p>La mercadería vuelve a donde salió y se descuenta de la cuenta del cliente.</p>
      <div class="campo"><label for="cancel-motivo">Motivo</label><input id="cancel-motivo" placeholder="Ej.: el cliente no estaba"></div>`,
      [{ texto: 'Volver', clase: 'sec', accion: () => true },
        { texto: 'Cancelar pedido', clase: 'peligro', accion: async () => {
          await rpc('cancelar_pedido', { p_pedido_id: p.id, p_motivo: $('#cancel-motivo').value.trim() || null });
          toast(`Pedido #${p.numero} cancelado`, 'ok');
          cargarPedidos();
          refrescarRecorrido();
        } }]);
  }

  function pedirDevolucion(p, items) {
    const disp = items.filter((i) => Number(i.cantidad) - Number(i.cantidad_devuelta) > 0);
    if (!disp.length) { toast('No queda nada para devolver en este pedido', 'error'); return; }
    const c = camionActual();
    dialogo(`Devolución · pedido #${p.numero}`, `
      <table>
        <thead><tr><th>Producto</th><th class="num">Vendido</th><th>Devuelve</th></tr></thead>
        <tbody>${disp.map((i, n) => `<tr><td>${esc(i.descripcion)}</td>
          <td class="num">${cant(Number(i.cantidad) - Number(i.cantidad_devuelta))} ${esc(i.unidad)}</td>
          <td><div class="cantidad"><input type="number" min="0" max="${Number(i.cantidad) - Number(i.cantidad_devuelta)}" step="${pasoCant(i.unidad)}" value="0" data-dev="${n}" inputmode="decimal" aria-label="Cantidad a devolver"></div></td></tr>`).join('')}</tbody>
      </table>
      <div class="campo" style="margin-top:12px"><label for="dev-motivo">Motivo</label><input id="dev-motivo" placeholder="Ej.: envase roto, vencido…"></div>
      <div class="campo"><label for="dev-destino">¿Qué se hace con la mercadería?</label>
        <select id="dev-destino">
          ${c ? `<option value="camion">Vuelve al camión ${esc(c.numero)}</option>` : ''}
          <option value="deposito">Vuelve al depósito</option>
          <option value="descarte">Se descarta (no vuelve al stock)</option>
        </select></div>`,
      [{ texto: 'Volver', clase: 'sec', accion: () => true },
        { texto: 'Registrar devolución', accion: async () => {
          const lineas = $$('[data-dev]', $('#dlg-cuerpo'))
            .map((inp) => ({ item: disp[Number(inp.dataset.dev)], cantidad: Number(inp.value) }))
            .filter((x) => x.cantidad > 0);
          if (!lineas.length) throw new Error('Indicá qué cantidad se devuelve');
          const destino = $('#dev-destino').value;
          const r = await rpc('registrar_devolucion', {
            p_pedido_id: p.id,
            p_items: lineas.map((x) => ({ codigo: x.item.codigo, cantidad: x.cantidad })),
            p_motivo: $('#dev-motivo').value.trim() || null,
            p_camion_id: destino === 'camion' ? c.id : null,
            p_vuelve_a_stock: destino !== 'descarte',
          });
          toast(`Devolución #${r.numero} por ${pesos(r.total)}. Saldo cliente: ${pesos(r.saldo_cliente)}`, 'ok', 5000);
          cargarPedidos();
        } }]);
  }

  // ================= CLIENTES =================
  const buscarListado = debounce(cargarClientes, 250);
  $('#clientes-buscar').addEventListener('input', buscarListado);
  $('#clientes-deudores').addEventListener('change', cargarClientes);
  let listadoClientes = [];

  async function cargarClientes() {
    const t = limpiarBusqueda($('#clientes-buscar').value);
    let q = sb.from('v_saldos').select('*').eq('activo', true).order('nombre').limit(60);
    if (t) q = /^\d+$/.test(t) ? q.or(`codigo.eq.${t},telefono.ilike.*${t}*`) : q.ilike('nombre', `%${t}%`);
    if ($('#clientes-deudores').checked) q = q.gt('saldo', 0);
    try {
      listadoClientes = await consulta(q);
      $('#clientes-lista').innerHTML = listadoClientes.map((c, i) => `
        <li class="clic" data-i="${i}">
          <div class="fila entre"><span><b>${esc(c.nombre)}</b> <span class="suave">#${c.codigo}</span></span>
            <span class="${Number(c.saldo) > 0 ? 'deuda' : 'suave'}">${pesos(c.saldo)}</span></div>
          <div class="suave">${esc([c.localidad, c.lista_precio, c.camion ? 'Camión ' + c.camion : null].filter(Boolean).join(' · '))}</div>
        </li>`).join('') || '<li class="vacio">Sin clientes.</li>';
    } catch (e) { toast(e.message, 'error'); }
  }

  $('#clientes-lista').addEventListener('click', (e) => {
    const li = e.target.closest('[data-i]');
    if (!li) return;
    const c = listadoClientes[Number(li.dataset.i)];
    const botones = [];
    const wa = linkWhatsapp(c.whatsapp, `Hola ${c.nombre}, te escribimos de Congelados Claudio.`);
    if (wa) botones.push({ texto: 'WhatsApp', clase: 'sec', href: wa });
    botones.push({ texto: 'Ver cuenta / cobrar', clase: 'sec', accion: () => { irA('cobrar'); elegirClienteCobro(c); } });
    if (E.puedeOperar) botones.push({ texto: 'Vender', accion: () => { irA('vender'); elegirClienteVenta(c); } });
    dialogo(c.nombre, `
      <p class="suave">Cliente #${c.codigo}</p>
      <table>
        <tr><th>Saldo</th><td class="${Number(c.saldo) > 0 ? 'deuda' : 'a-favor'}">${pesos(c.saldo)}</td></tr>
        <tr><th>Condición</th><td>${c.condicion_pago === 'cta_cte' ? 'Cuenta corriente' : 'Contado'}${Number(c.limite_credito) > 0 ? ' · límite ' + pesos(c.limite_credito) : ''}</td></tr>
        <tr><th>Lista</th><td>${esc(c.lista_precio || 'Base')}</td></tr>
        <tr><th>Teléfono</th><td>${esc(c.telefono || '—')}</td></tr>
        <tr><th>Localidad</th><td>${esc(c.localidad || '—')}</td></tr>
        <tr><th>Camión</th><td>${esc(c.camion || '—')}</td></tr>
        <tr><th>Última compra</th><td>${esc(fechaCorta(c.ultima_compra) || '—')}</td></tr>
        <tr><th>Último pago</th><td>${esc(fechaCorta(c.ultimo_pago) || '—')}</td></tr>
      </table>`, botones);
  });

  $('#btn-nuevo-cliente').addEventListener('click', () => {
    dialogo('Nuevo cliente', `
      <div class="campo"><label for="nc-nombre">Nombre *</label><input id="nc-nombre" required></div>
      <div class="campo"><label for="nc-dir">Dirección</label><input id="nc-dir"></div>
      <div class="grilla-2">
        <div class="campo"><label for="nc-loc">Localidad</label><input id="nc-loc"></div>
        <div class="campo"><label for="nc-wa">WhatsApp</label><input id="nc-wa" inputmode="tel" placeholder="11 2345 6789"></div>
      </div>
      <div class="grilla-2">
        <div class="campo"><label for="nc-lista">Lista de precios</label>
          <select id="nc-lista"><option value="">Base</option>${E.listas.map((l) => `<option value="${l.id}">${esc(l.nombre)}</option>`).join('')}</select></div>
        <div class="campo"><label for="nc-cond">Condición</label>
          <select id="nc-cond"><option value="contado">Contado</option><option value="cta_cte">Cuenta corriente</option></select></div>
      </div>`,
    [{ texto: 'Cancelar', clase: 'sec', accion: () => true },
      { texto: 'Guardar', clase: 'ok', accion: async () => {
        const nombre = $('#nc-nombre').value.trim();
        if (!nombre) throw new Error('El nombre es obligatorio');
        const wa = $('#nc-wa').value.trim() || null;
        const nuevo = await consulta(sb.from('clientes').insert({
          nombre, direccion: $('#nc-dir').value.trim() || null, localidad: $('#nc-loc').value.trim() || null,
          telefono: wa, whatsapp: wa, lista_precio_id: $('#nc-lista').value || null,
          condicion_pago: $('#nc-cond').value, camion_id: E.camionId,
        }).select('id, codigo').single());
        toast(`Cliente #${nuevo.codigo} creado`, 'ok');
        $('#clientes-buscar').value = nombre;
        cargarClientes();
      } }]);
    setTimeout(() => $('#nc-nombre').focus(), 50);
  });

  // ================= Inicio =================
  ajustarOrigenVenta();
  await refrescarRecorrido();
  irA(E.puedeOperar ? (leer('tab') || 'vender') : (leer('tab') === 'vender' ? 'pedidos' : (leer('tab') || 'pedidos')));
})();
