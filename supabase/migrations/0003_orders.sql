-- 0003_orders.sql
--
-- Closes TBD-02, the largest gap between the SRS and the build. Until now a
-- confirmed cart was written nowhere and the staff queue rendered five
-- hardcoded rows.
--
-- Four new tables plus the staff/cafeteria binding that finally enforces BR-3
-- ("a staff member may manage only the cafeteria they are responsible for").

-- ------------------------------------------------------------------ enums --
do $$ begin
  create type public.order_status as enum
    ('new', 'preparing', 'ready', 'collected', 'cancelled');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.payment_method as enum ('cash', 'card');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.payment_state as enum
    ('pending', 'paid', 'failed', 'refunded');
exception when duplicate_object then null; end $$;

-- -------------------------------------------------------- staff_cafeterias --
-- This table, not profiles.role, is the authorisation boundary. A user may
-- self-assert role='staff' at signup (the client passes it in auth metadata),
-- but that grants nothing on its own: every staff write policy in 0006 checks
-- membership here, which only an administrator can grant.
create table if not exists public.staff_cafeterias (
  staff_id     uuid not null references public.profiles (id) on delete cascade,
  cafeteria_id uuid not null references public.cafeterias (id) on delete cascade,
  granted_at   timestamptz not null default now(),
  primary key (staff_id, cafeteria_id)
);

comment on table public.staff_cafeterias is
  'Authorisation boundary for staff writes (BR-3). Seeded by an administrator, never by the app.';

-- ------------------------------------------------------- collection refs --
-- REQ-61. Six characters from an alphabet with no visually ambiguous glyphs
-- (no 0/O, no 1/I), random rather than sequential so one reference does not
-- reveal another. ~887m combinations; place_order retries on collision.
create or replace function public.gen_collection_ref()
returns text
language plpgsql
volatile
as $$
declare
  alphabet constant text := 'ACDEFGHJKLMNPQRSTUVWXYZ23456789';
  result   text := '';
  i        integer;
begin
  for i in 1 .. 6 loop
    result := result || substr(alphabet, 1 + floor(random() * length(alphabet))::integer, 1);
  end loop;
  return result;
end;
$$;

-- ------------------------------------------------------------------ orders --
create table if not exists public.orders (
  id                  uuid primary key default gen_random_uuid(),
  student_id          uuid not null references public.profiles (id) on delete restrict,
  cafeteria_id        uuid not null references public.cafeterias (id) on delete restrict,
  status              public.order_status  not null default 'new',
  payment_method      public.payment_method not null,
  payment_state       public.payment_state not null default 'pending',
  total_cents         integer not null check (total_cents >= 0),
  collection_ref      text not null unique,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  collected_at        timestamptz,
  cancelled_at        timestamptz,
  cancellation_reason text
);

create index if not exists orders_cafeteria_status_idx
  on public.orders (cafeteria_id, status, created_at desc);
create index if not exists orders_student_idx
  on public.orders (student_id, created_at desc);

-- ------------------------------------------------------------- order_items --
-- Name and unit price are snapshotted: menu prices change, and an order is a
-- historical record of what was actually charged.
create table if not exists public.order_items (
  id               uuid primary key default gen_random_uuid(),
  order_id         uuid not null references public.orders (id) on delete cascade,
  menu_item_id     uuid references public.menu_items (id) on delete set null,
  name             text not null,
  unit_price_cents integer not null check (unit_price_cents >= 0),
  quantity         integer not null check (quantity > 0)
);

create index if not exists order_items_order_idx on public.order_items (order_id);

-- ---------------------------------------------------------------- payments --
create table if not exists public.payments (
  id                 uuid primary key default gen_random_uuid(),
  order_id           uuid not null references public.orders (id) on delete cascade,
  provider           text not null default 'paystack',
  provider_reference text not null unique,
  amount_cents       integer not null check (amount_cents >= 0),
  currency           text not null default 'ZAR',
  status             text not null default 'pending'
                       check (status in ('pending', 'success', 'failed', 'abandoned')),
  raw_response       jsonb,
  created_at         timestamptz not null default now(),
  verified_at        timestamptz
);

comment on column public.payments.provider_reference is
  'Unique per transaction. This is the idempotency key shared by the verify call and the webhook.';

create index if not exists payments_order_idx on public.payments (order_id);

-- ------------------------------------------------------- stock_reservations --
-- REQ-51. Stock is decremented at add-to-cart time, which makes it a
-- reservation. Today that reservation has no owner and no expiry, so an
-- abandoned cart strands stock permanently. These three columns are what make
-- the sweep in 0004 possible.
create table if not exists public.stock_reservations (
  id           uuid primary key default gen_random_uuid(),
  menu_item_id uuid not null references public.menu_items (id) on delete cascade,
  student_id   uuid not null references public.profiles (id) on delete cascade,
  quantity     integer not null check (quantity > 0),
  order_id     uuid references public.orders (id) on delete set null,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default now() + interval '30 minutes'
);

-- One open reservation row per student per item; converted rows (order_id set)
-- are historical and excluded.
create unique index if not exists stock_reservations_open_unique
  on public.stock_reservations (menu_item_id, student_id)
  where order_id is null;

create index if not exists stock_reservations_expiry_idx
  on public.stock_reservations (expires_at)
  where order_id is null;

-- ------------------------------------------------------------ updated_at --
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists orders_touch_updated_at on public.orders;
create trigger orders_touch_updated_at
  before update on public.orders
  for each row execute function public.touch_updated_at();
