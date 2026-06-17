# EventPay v2.0 🎟
Sistema de punto de venta cashless para eventos.
Mercado Pago Point Deep Link + Supabase Realtime + PWA instalable.

---

## Arquitectura

```
Tu PC / celular  →  admin.html   →  Dashboard, catálogo en vivo, cajeros, reportes
Posnet / tablet  →  cajero.html  →  POS: catálogo, carrito, cobro MP, ticket, devoluciones
         ↑                ↑
         └─── Supabase ───┘  (sync en tiempo real < 1 segundo)
                   ↑
            MP Point Deep Link
         (abre la app nativa de MP)
```

---

## PASO A PASO COMPLETO

### PARTE 1 — Base de datos (Supabase, gratis)

1. Ir a https://supabase.com → crear cuenta → New project
   - Nombre: "eventpay"
   - Región: South America (São Paulo)

2. SQL Editor → New query → pegar todo el contenido de `schema.sql` → Run

3. Project Settings → API → copiar:
   - **Project URL** → `https://abcxyz.supabase.co`
   - **anon public key** → `eyJ...` (clave larga)

4. Abrir `js/config.js` y pegar los valores:
   ```js
   const SUPABASE_URL = 'https://abcxyz.supabase.co';
   const SUPABASE_KEY = 'eyJ...tu_anon_key...';
   ```

---

### PARTE 2 — App ID de Mercado Pago (para el Deep Link)

1. Ir a https://www.mercadopago.com.ar/developers
2. Mis integraciones → Crear aplicación
   - Nombre: "EventPay"
   - Solución de pago: **Pagos en persona** (Point)
3. Guardar el **Application ID** (número largo)
4. Agregarlo en `js/config.js`:
   ```js
   const MP_APP_ID = '123456789'; // tu Application ID
   ```

---

### PARTE 3 — Publicar en internet (Vercel, gratis)

1. Crear cuenta en https://github.com
2. New repository → nombre: "eventpay" → Public → Create
3. Subir los archivos:
   - Ir al repo → "uploading an existing file"
   - Arrastrá toda la carpeta `eventpay-v3` descomprimida → Commit
4. Ir a https://vercel.com → Add New Project → importar "eventpay"
5. Deploy → en 30 segundos obtenés la URL:
   `https://eventpay-tuusuario.vercel.app`

URLs del sistema:
- **Admin (tu PC):**  https://eventpay-tuusuario.vercel.app/admin.html
- **Cajero (posnet):** https://eventpay-tuusuario.vercel.app/cajero.html

---

### PARTE 4 — Instalar en el Point Smart (PWA)

El posnet Point Smart corre Android con browser Chrome.
La app `cajero.html` es una PWA (Progressive Web App) — se instala
como app nativa sin pasar por ninguna tienda.

**Pasos en el posnet:**

1. Abrir el browser (ícono de globo en la pantalla del posnet)
2. Escribir la URL: `https://eventpay-tuusuario.vercel.app/cajero.html`
3. El browser muestra un banner "Agregar a pantalla de inicio" → tocar
   (o menú ☰ → "Instalar aplicación")
4. La app queda instalada como ícono en la pantalla principal
5. La próxima vez se abre directo, sin escribir la URL, en modo pantalla completa

**Si no aparece el banner:**
- Menú del browser (⋮) → "Agregar a pantalla de inicio"
- O en Chrome → menú → "Instalar EventPay"

---

### PARTE 5 — Cómo funciona el cobro con tarjeta/QR

#### Flujo completo en el posnet:

```
1. Cajero arma el carrito en EventPay
2. Toca "Cobrar" → elige Tarjeta o QR
3. EventPay muestra el botón "📲 Abrir Mercado Pago"
4. Al tocar → se abre la app nativa de MP en el posnet
5. El cliente pasa la tarjeta / escanea el QR en el posnet
6. MP procesa el pago y llama a la success_url o failure_url
7. EventPay retoma el control y muestra:
   - ✅ Pago aprobado → genera el ticket con el MP Payment ID
   - ❌ Pago rechazado → ofrece reintentar o cancelar
```

#### Deep Link que se dispara (código en cajero.html):
```
https://secure.mlstatic.com/org-img/point/app/index.html
  ?amount=1800.00
  &description=Fernet c/Coca x1
  &success_url=https://eventpay.vercel.app/cajero.html?mp_result=success&orden_id=0001
  &failure_url=https://eventpay.vercel.app/cajero.html?mp_result=failure&orden_id=0001
  &app_id=TU_APP_ID
```

#### Parámetros que recibe el callback:
- `mp_result`: "success" o "failure"
- `orden_id`: identificador interno de la orden
- `amount`: monto cobrado
- `payment_id` (cuando MP lo incluye): ID del pago en MP

---

### PARTE 6 — Cobro con efectivo

El efectivo no pasa por el posnet de MP.
EventPay lo registra directamente:
1. Cajero selecciona "Efectivo"
2. Toca "Cobrar" → se confirma automáticamente en 1.5s
3. Genera el ticket de consumición sin pasar por MP

---

### PARTE 7 — Devoluciones

En el posnet, el cajero puede ver el historial del turno y devolver órdenes:
1. Ícono 🧾 en el POS → lista de órdenes del turno
2. Cada orden pagada tiene el botón "↩ Devolver"
3. Al confirmar → la orden queda marcada como "devuelta" en la DB
4. El admin lo ve en el dashboard en tiempo real

---

## Archivos del proyecto

```
eventpay-v3/
├── index.html      → Pantalla de inicio (elige cajero o admin)
├── admin.html      → Panel de administración completo
├── cajero.html     → POS para posnet (Deep Link MP + PWA)
├── manifest.json   → Configuración PWA (para instalar en posnet)
├── schema.sql      → Base de datos Supabase (ejecutar una sola vez)
├── js/
│   └── config.js   → ⚠️  TUS CREDENCIALES VAN ACÁ
└── README.md       → Este archivo
```

---

## Lo que hace cada archivo

**cajero.html**
- PWA instalable en el posnet
- Catálogo sincronizado en tiempo real desde Supabase
- Carrito con control de cantidades
- 4 métodos de pago: Tarjeta, QR, Efectivo, Combinado
- Deep Link real a Mercado Pago (`secure.mlstatic.com/org-img/point/app/index.html`)
- Callback handler: procesa el resultado de MP al volver
- Ticket de consumición con MP Payment ID
- Historial del turno con devoluciones
- Cierre de caja con desglose por método de pago

**admin.html**
- Dashboard con métricas en tiempo real
- Gestión de catálogo (agregar, editar, ocultar, eliminar)
- Cambios en el catálogo → aparecen en el posnet en < 1 segundo
- Lista de cajeros activos y historial de turnos
- Órdenes con filtros y exportación CSV
- Ventas por stand y por medio de pago

**schema.sql**
- Tablas: eventos, stands, productos, cajeros, ordenes, transacciones
- Vistas: ventas_por_producto, ventas_por_stand, ventas_por_cajero
- Políticas RLS y configuración de Realtime

---

## Próximos pasos (cuando estés listo)

- [ ] Backend Node.js para MP Point API (cobro server-side más seguro)
- [ ] Impresora térmica Bluetooth 58mm (ticket físico real)
- [ ] Auth con contraseña para el panel admin
- [ ] Multi-evento con selector en login
- [ ] Webhook de MP para confirmar pagos server-side

---

## Tecnologías
- HTML / CSS / JS puro — funciona en cualquier browser
- Supabase — PostgreSQL + Realtime + Row Level Security
- Vercel — hosting estático gratuito
- PWA — instalable en Android sin app store
- Mercado Pago Point Deep Link — integración nativa con el posnet
