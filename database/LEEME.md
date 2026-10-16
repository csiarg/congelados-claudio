# Congelados Claudio · Base de datos v2

Reemplaza a `schema_congelados_claudio.sql` (el anterior no llegaba a ejecutarse: tenía un trigger con sintaxis inválida y el control de stock no filtraba por camión).

## Instalación en Supabase (paso a paso)

1. **Crear el proyecto** en https://supabase.com → *New project*. Región: **São Paulo (sa-east-1)**. Guardá la contraseña de la base.
2. **Instalar la base**: *SQL Editor* → *New query* → pegar todo `00_INSTALAR_TODO.sql` → **Run**. Tiene que terminar en "Success. No rows returned".
3. **Crear tu usuario**: *Authentication* → *Users* → *Add user* → *Create new user* (tildar *Auto Confirm User*). **El primer usuario creado queda como admin**; los siguientes entran como `consulta` y los subís de rol desde la tabla `perfiles`.
4. **(Opcional) Datos de prueba**: pegar y ejecutar `05_datos_demo.sql` (15 productos, 6 clientes, 2 camiones, compras iniciales).
5. **Cortar el registro público**: *Authentication* → *Sign In / Providers* → desactivar *Allow new users to sign up*. Los usuarios los crea el admin.
6. **Anotar las claves** en *Project Settings* → *API*: `Project URL`, `anon public` (va en la web) y `service_role` (solo en Netlify, para WhatsApp; **nunca** en el navegador).

Antes de cargar los datos reales: ejecutar `99_limpiar_datos.sql` (borra todo menos usuarios y configuración).

## Archivos

| Archivo | Qué hace | ¿Re-ejecutable? |
|---|---|---|
| `00_INSTALAR_TODO.sql` | 01 + 02 + 03 + 04 juntos | No (instalación nueva) |
| `01_estructura.sql` | Tablas, índices, triggers | No |
| `02_funciones.sql` | Lógica de negocio | Sí, para actualizar |
| `03_vistas.sql` | Consultas para pantallas | Sí |
| `04_seguridad.sql` | Permisos por rol | Sí |
| `05_datos_demo.sql` | Datos de prueba | Una vez |
| `99_limpiar_datos.sql` | Borra datos (no usuarios) | ⚠️ |
| `pruebas/` | Pruebas automáticas en Postgres local. **No van en Supabase** | — |

## Cómo funciona

**Stock en dos lugares.** Depósito (`camion_id` vacío) y cada camión. Nadie escribe el stock a mano: todo pasa por funciones que dejan registro en `movimientos_stock` (kardex).

```
Compra al proveedor ──► DEPÓSITO ──cargar_camion──► CAMIÓN ──venta──► cliente
                           ▲                          │
                           └──descargar / cerrar──────┘   (lo que sobró vuelve)
Pedido WhatsApp ──► sale del DEPÓSITO, queda "pendiente" para el camión del cliente
```

**Costo promedio ponderado.** Cada compra recalcula: `(stock × costo actual + cantidad comprada × costo nuevo) ÷ (stock + cantidad)`. Con 100 u a $1 y 100 u compradas a $1,20 → **$1,10**. Si el producto tiene `margen_porcentaje`, el precio de venta se actualiza solo y queda en `precios_historico`.

**Listas de precios.** Precio base del producto × % de la lista (−10 = 10 % de descuento). Para casos puntuales: precio especial por producto en `listas_precios_items`.

**Cuenta corriente.** Libro debe/haber por cliente (`cta_cte_movimientos`). Venta = debe, pago/devolución/cancelación = haber. El saldo se calcula (vista `v_saldos`), no se guarda, así nunca se desfasa. `limite_credito` > 0 bloquea ventas que lo superen (el admin puede pasarlo por alto).

**Roles.** `admin`: todo. `operario`: vende, cobra, devuelve, carga y descarga camiones, da de alta clientes. `consulta`: solo mira. Usuario inactivo o sin perfil: no ve nada.

## Funciones (se llaman con `supabase.rpc('nombre', {...})`)

| Función | Rol | Para qué |
|---|---|---|
| `crear_pedido(p_cliente_id, p_items, p_camion_id?, p_origen?, p_notas?, p_pago_monto?, p_pago_medio?)` | operario | Venta. Con camión: sale del camión y queda entregada. Sin camión: sale del depósito, queda pendiente |
| `marcar_entregado(p_pedido_id)` | operario | Pendiente → entregado |
| `cancelar_pedido(p_pedido_id, p_motivo?)` | operario (pendientes) / admin | Devuelve stock y revierte la cuenta |
| `registrar_devolucion(p_pedido_id, p_items, p_motivo?, p_camion_id?, p_vuelve_a_stock?)` | operario | Devolución parcial |
| `registrar_pago(p_cliente_id, p_monto, p_medio?, p_referencia?, p_camion_id?)` | operario | Cobranza |
| `cargar_camion(p_camion_id, p_items)` / `descargar_camion(p_camion_id, p_items?)` | operario | Movimientos depósito ↔ camión |
| `cerrar_recorrido(p_camion_id, p_descargar?)` | operario | Fin de jornada: descarga y devuelve resumen |
| `registrar_compra(p_items, p_proveedor_id?, p_comprobante?)` | admin | Ingreso de mercadería + costo promedio |
| `actualizar_precio` / `aumentar_precios(p_porcentaje, p_proveedor_id?, p_rubro?)` | admin | Precios |
| `ajustar_stock(p_producto_id, p_cantidad_real, p_camion_id?, p_motivo?, p_es_merma?)` | admin | Conteo físico / mermas |
| `ajustar_cta_cte(p_cliente_id, p_monto, p_motivo, p_es_saldo_inicial?)` | admin | Saldos iniciales y ajustes |
| `anular_pago(p_pago_id, p_motivo?)` | admin | |
| `buscar_productos(p_termino, p_lista_id?, p_camion_id?)` | todos | Buscador con precio y stock |
| `top_productos(p_desde?, p_hasta?, p_camion_id?, p_proveedor_id?, p_limite?)` | todos | TOP 10 (últimos 30 días por defecto) |
| `resumen_dashboard(p_desde?, p_hasta?)` | todos | Ventas, ganancia, cobranzas, deuda, stock valorizado |
| `catalogo_whatsapp(p_whatsapp)` / `crear_pedido_whatsapp(p_whatsapp, p_items)` | solo servidor | Bot de WhatsApp |

`p_items` siempre es una lista: `[{"codigo": "POL01", "cantidad": 5}]` (o `producto_id` en lugar de `codigo`).

**Vistas:** `v_stock`, `v_stock_camiones`, `v_saldos`, `v_cta_cte`, `v_pedidos`, `v_pedidos_items`, `v_ventas_diarias`, `v_movimientos_stock`.

## Pruebas

`pruebas/01_prueba_flujo.sql` recorre un día completo (carga de camión, ventas, devolución, cobro, límite de crédito, pedido por WhatsApp, compra con costo promedio, cancelación, cierre, TOP 10 y permisos de cada rol). Se corre en un Postgres local después de `pruebas/00_simular_supabase.sql`, la instalación y los datos demo.
