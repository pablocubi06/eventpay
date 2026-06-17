-- ============================================================
--  EventPay — Supabase Schema
--  Ejecutar en: Supabase > SQL Editor > New query
-- ============================================================

-- ── Extensiones ──────────────────────────────────────────────
create extension if not exists "uuid-ossp";

-- ── Limpiar (si ya existe una versión anterior) ───────────────
drop table if exists transacciones  cascade;
drop table if exists ordenes        cascade;
drop table if exists cajeros        cascade;
drop table if exists productos      cascade;
drop table if exists stands         cascade;
drop table if exists eventos        cascade;

-- ============================================================
--  1. EVENTOS
-- ============================================================
create table eventos (
  id          uuid primary key default uuid_generate_v4(),
  nombre      text not null,
  fecha       date,
  lugar       text,
  activo      boolean default true,
  created_at  timestamptz default now()
);

-- Evento de ejemplo
insert into eventos (nombre, fecha, lugar) values
  ('Festival Verano 2025', '2025-02-15', 'Predio La Rural'),
  ('Fiesta de Fin de Año',  '2025-12-31', 'Club House Norte');

-- ============================================================
--  2. STANDS
-- ============================================================
create table stands (
  id          uuid primary key default uuid_generate_v4(),
  evento_id   uuid references eventos(id) on delete cascade,
  nombre      text not null,
  descripcion text,
  activo      boolean default true,
  created_at  timestamptz default now()
);

insert into stands (evento_id, nombre) 
select id, nombre_stand from eventos cross join (
  values 
    ('Bar Principal'),
    ('Foodtruck'),
    ('VIP Lounge'),
    ('Cócteles'),
    ('Snacks'),
    ('Caja Central')
) as s(nombre_stand)
where eventos.nombre = 'Festival Verano 2025';

-- ============================================================
--  3. PRODUCTOS
-- ============================================================
create table productos (
  id            uuid primary key default uuid_generate_v4(),
  evento_id     uuid references eventos(id) on delete cascade,
  nombre        text not null,
  descripcion   text,
  precio        numeric(10,2) not null check (precio >= 0),
  categoria     text not null default 'General',
  emoji         text default '🍺',
  es_promo      boolean default false,
  promo_desc    text,
  disponible    boolean default true,
  orden         int default 0,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

-- Trigger: actualizar updated_at automáticamente
create or replace function set_updated_at()
returns trigger as $$
begin new.updated_at = now(); return new; end;
$$ language plpgsql;

create trigger productos_updated_at
  before update on productos
  for each row execute function set_updated_at();

-- Productos de ejemplo para Festival Verano 2025
insert into productos (evento_id, nombre, precio, categoria, emoji, es_promo, promo_desc, orden)
select e.id, p.nombre, p.precio, p.categoria, p.emoji, p.es_promo, p.promo_desc, p.orden
from eventos e cross join (values
  ('Fernet c/Coca',   1800, 'Tragos',     '🥃', false, null,                  1),
  ('Cerveza porrón',  1200, 'Cervezas',   '🍺', false, null,                  2),
  ('Cerveza chopera',  900, 'Cervezas',   '🍻', false, null,                  3),
  ('Gaseosa',          600, 'Sin alcohol','🥤', false, null,                  4),
  ('Agua mineral',     400, 'Sin alcohol','💧', false, null,                  5),
  ('Vodka c/jugo',    2000, 'Tragos',     '🍹', false, null,                  6),
  ('Gin tónico',      2200, 'Tragos',     '🍸', false, null,                  7),
  ('Whisky c/soda',   2500, 'Tragos',     '🥃', false, null,                  8),
  ('2x1 Fernet 🔥',   2800, 'Promos',     '🥃', true,  'Vale por 2 Fernets', 9),
  ('2x1 Cerveza 🔥',  1800, 'Promos',     '🍺', true,  'Vale por 2 cervezas',10),
  ('Combo VIP ⭐',    4500, 'Promos',     '⭐', true,  '1 trago + 2 birras', 11),
  ('Botella vodka',  12000, 'Botellería', '🍾', false, null,                  12),
  ('Botella gin',    14000, 'Botellería', '🫙', false, null,                  13),
  ('Botella whisky', 18000, 'Botellería', '🥃', false, null,                  14)
) as p(nombre, precio, categoria, emoji, es_promo, promo_desc, orden)
where e.nombre = 'Festival Verano 2025';

-- ============================================================
--  4. CAJEROS (sesiones de turno)
-- ============================================================
create table cajeros (
  id            uuid primary key default uuid_generate_v4(),
  evento_id     uuid references eventos(id) on delete cascade,
  stand_id      uuid references stands(id),
  nombre        text not null,
  stand_nombre  text,               -- desnormalizado para reportes rápidos
  hora_entrada  timestamptz default now(),
  hora_cierre   timestamptz,
  activo        boolean default true,
  -- Resumen del turno (se llena al cerrar)
  total_ventas  numeric(12,2) default 0,
  total_tx      int default 0,
  total_digital numeric(12,2) default 0,
  total_efectivo numeric(12,2) default 0,
  created_at    timestamptz default now()
);

-- ============================================================
--  5. ORDENES
-- ============================================================
create table ordenes (
  id                uuid primary key default uuid_generate_v4(),
  evento_id         uuid references eventos(id),
  cajero_id         uuid references cajeros(id),
  stand_nombre      text,
  cajero_nombre     text,
  numero_orden      text not null,          -- "0001", "0002", ...
  items             jsonb not null,          -- [{id, nombre, emoji, precio, qty, promo_desc}]
  total             numeric(10,2) not null,
  metodo_pago       text not null,          -- tarjeta | qr | efectivo | combinado
  monto_efectivo    numeric(10,2) default 0,
  monto_digital     numeric(10,2) default 0,
  -- Mercado Pago
  mp_order_id       text,                   -- id devuelto por MP /v1/orders
  mp_payment_id     text,                   -- transactions.payments.id
  mp_status         text default 'pending', -- pending | approved | rejected | cancelled
  -- Estado interno
  estado            text default 'pagada',  -- pagada | anulada | devuelta
  created_at        timestamptz default now()
);

-- ============================================================
--  6. TRANSACCIONES (detalle por producto para analytics)
-- ============================================================
create table transacciones (
  id            uuid primary key default uuid_generate_v4(),
  orden_id      uuid references ordenes(id) on delete cascade,
  evento_id     uuid references eventos(id),
  producto_id   uuid references productos(id),
  producto_nombre text,
  producto_emoji  text,
  categoria     text,
  cantidad      int not null,
  precio_unit   numeric(10,2) not null,
  subtotal      numeric(10,2) not null,
  created_at    timestamptz default now()
);

-- ============================================================
--  7. VISTAS útiles
-- ============================================================

-- Ventas por producto (para dashboard)
create or replace view v_ventas_por_producto as
select
  t.evento_id,
  t.producto_id,
  t.producto_nombre,
  t.producto_emoji,
  t.categoria,
  sum(t.cantidad)  as unidades,
  sum(t.subtotal)  as total
from transacciones t
join ordenes o on o.id = t.orden_id
where o.estado = 'pagada'
group by t.evento_id, t.producto_id, t.producto_nombre, t.producto_emoji, t.categoria
order by total desc;

-- Ventas por stand (para dashboard)
create or replace view v_ventas_por_stand as
select
  evento_id,
  stand_nombre,
  count(*)          as ordenes,
  sum(total)        as total,
  sum(monto_efectivo) as efectivo,
  sum(monto_digital)  as digital
from ordenes
where estado = 'pagada'
group by evento_id, stand_nombre
order by total desc;

-- Ventas por cajero (para cierre)
create or replace view v_ventas_por_cajero as
select
  c.id as cajero_id,
  c.nombre,
  c.stand_nombre,
  c.hora_entrada,
  c.hora_cierre,
  c.activo,
  coalesce(sum(o.total), 0)           as total,
  coalesce(count(o.id), 0)            as tx_count,
  coalesce(sum(o.monto_digital), 0)   as digital,
  coalesce(sum(o.monto_efectivo), 0)  as efectivo
from cajeros c
left join ordenes o on o.cajero_id = c.id and o.estado = 'pagada'
group by c.id, c.nombre, c.stand_nombre, c.hora_entrada, c.hora_cierre, c.activo
order by c.hora_entrada desc;

-- ============================================================
--  8. ROW LEVEL SECURITY
--  Para producción: habilitar y configurar según roles.
--  Por ahora usamos anon key con acceso total (dev mode).
-- ============================================================

alter table eventos     enable row level security;
alter table stands      enable row level security;
alter table productos   enable row level security;
alter table cajeros     enable row level security;
alter table ordenes     enable row level security;
alter table transacciones enable row level security;

-- Políticas permisivas para anon (cambiar en producción por roles)
create policy "anon_all_eventos"      on eventos      for all using (true) with check (true);
create policy "anon_all_stands"       on stands       for all using (true) with check (true);
create policy "anon_all_productos"    on productos    for all using (true) with check (true);
create policy "anon_all_cajeros"      on cajeros      for all using (true) with check (true);
create policy "anon_all_ordenes"      on ordenes      for all using (true) with check (true);
create policy "anon_all_transacc"     on transacciones for all using (true) with check (true);

-- ============================================================
--  9. REALTIME — habilitar tablas para sync en vivo
-- ============================================================
-- Ejecutar esto en SQL Editor para agregar tablas al canal realtime:
alter publication supabase_realtime add table productos;
alter publication supabase_realtime add table ordenes;
alter publication supabase_realtime add table cajeros;

-- ============================================================
--  FIN
--  Próximos pasos:
--  1. Copiar SUPABASE_URL y SUPABASE_ANON_KEY desde
--     Project Settings > API en tu proyecto de Supabase
--  2. Pegarlos en cajero.html y admin.html donde dice CONFIG
-- ============================================================
