-- 0010_repair_orders.sql
--
-- Run AFTER 0009. Idempotent: safe to run more than once.
--
-- Why this exists. The hosted project already had `orders` and `order_items`
-- tables from before these migrations, so 0003's `create table if not exists`
-- skipped them. They kept their old shape:
--
--   orders:      id, student_id, cafeteria_id, status text default 'pending'
--                (check: pending/preparing/ready/completed/cancelled),
--                total_amount numeric NOT NULL, created_at
--   order_items: id, order_id, menu_item_id, quantity, unit_price numeric NOT NULL
--
-- place_order (0004/0008/0009) writes payment_method, total_cents and
-- collection_ref, so EVERY checkout — cash or card — failed with
--   column "payment_method" of relation "orders" does not exist
-- and the app showed "Something went wrong". The live orders_touch_updated_at
-- trigger also writes a missing updated_at column, so advancing or cancelling
-- would have failed next.
--
-- This brings both tables to the shape 0003 intended, checking what exists
-- first rather than assuming, and removes three things left over from the
-- old schema that bypass the rules in 0006.

-- ------------------------------------------------------------------ enums --
do $$
begin
  if not exists (select 1 from pg_type where typname = 'order_status') then
    create type public.order_status as enum
      ('new', 'preparing', 'ready', 'collected', 'cancelled');
  end if;
  if not exists (select 1 from pg_type where typname = 'payment_method') then
    create type public.payment_method as enum ('cash', 'card');
  end if;
  if not exists (select 1 from pg_type where typname = 'payment_state') then
    create type public.payment_state as enum
      ('pending', 'paid', 'failed', 'refunded');
  end if;
end;
$$;

-- ----------------------------------------------------------------- orders --

-- The old check allows 'pending' and 'completed', which are not order states.
alter table public.orders drop constraint if exists orders_status_check;

-- status: text -> order_status, mapping the old words onto the new ones.
do $$
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'orders'
       and column_name = 'status' and udt_name = 'text'
  ) then
    alter table public.orders alter column status drop default;

    update public.orders
       set status = case status
                      when 'pending'   then 'new'
                      when 'completed' then 'collected'
                      else status
                    end
     where status in ('pending', 'completed') or status is null;

    update public.orders set status = 'new' where status is null;

    alter table public.orders
      alter column status type public.order_status
      using status::public.order_status;
  end if;
end;
$$;

alter table public.orders alter column status set default 'new';
alter table public.orders alter column status set not null;

alter table public.orders
  add column if not exists payment_method public.payment_method not null default 'cash';
alter table public.orders
  add column if not exists payment_state public.payment_state not null default 'pending';
alter table public.orders
  add column if not exists total_cents integer not null default 0;
alter table public.orders
  add column if not exists collection_ref text;
alter table public.orders
  add column if not exists updated_at timestamptz not null default now();
alter table public.orders add column if not exists collected_at timestamptz;
alter table public.orders add column if not exists cancelled_at timestamptz;
alter table public.orders add column if not exists cancellation_reason text;

-- place_order always states the method; the default above only existed to
-- fill any old rows.
alter table public.orders alter column payment_method drop default;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'orders_total_cents_check'
  ) then
    alter table public.orders
      add constraint orders_total_cents_check check (total_cents >= 0);
  end if;
end;
$$;

-- Legacy money column: carry any old totals across, then stop requiring it
-- (place_order writes total_cents only).
do $$
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'orders'
       and column_name = 'total_amount'
  ) then
    update public.orders
       set total_cents = round(total_amount * 100)::integer
     where total_cents = 0 and total_amount is not null;
    alter table public.orders alter column total_amount drop not null;
  end if;
end;
$$;

-- Every order needs the short code staff match against the queue (REQ-61).
update public.orders
   set collection_ref = public.gen_collection_ref()
 where collection_ref is null;

alter table public.orders alter column collection_ref set not null;
create unique index if not exists orders_collection_ref_key
  on public.orders (collection_ref);

-- An order always belongs to a student and a cafeteria.
do $$
begin
  if not exists (select 1 from public.orders where student_id is null) then
    alter table public.orders alter column student_id set not null;
  end if;
  if not exists (select 1 from public.orders where cafeteria_id is null) then
    alter table public.orders alter column cafeteria_id set not null;
  end if;
end;
$$;

update public.orders set created_at = now() where created_at is null;
alter table public.orders alter column created_at set not null;

create index if not exists orders_student_idx   on public.orders (student_id, created_at desc);
create index if not exists orders_cafeteria_idx on public.orders (cafeteria_id, status, created_at);

-- The trigger was live but its column was not; now both exist.
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

-- ------------------------------------------------------------ order_items --
alter table public.order_items add column if not exists name text;
alter table public.order_items add column if not exists unit_price_cents integer;

update public.order_items oi
   set name = coalesce(m.name, 'Item')
  from public.menu_items m
 where oi.name is null and m.id = oi.menu_item_id;
update public.order_items set name = 'Item' where name is null;
alter table public.order_items alter column name set not null;

do $$
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'order_items'
       and column_name = 'unit_price'
  ) then
    update public.order_items
       set unit_price_cents = round(unit_price * 100)::integer
     where unit_price_cents is null and unit_price is not null;
    alter table public.order_items alter column unit_price drop not null;
  end if;
end;
$$;

update public.order_items set unit_price_cents = 0 where unit_price_cents is null;
alter table public.order_items alter column unit_price_cents set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'order_items_unit_price_cents_check'
  ) then
    alter table public.order_items
      add constraint order_items_unit_price_cents_check
      check (unit_price_cents >= 0);
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'order_items_quantity_check'
  ) then
    alter table public.order_items
      add constraint order_items_quantity_check check (quantity > 0);
  end if;
  if not exists (select 1 from public.order_items where order_id is null) then
    alter table public.order_items alter column order_id set not null;
  end if;
end;
$$;

create index if not exists order_items_order_idx on public.order_items (order_id);

-- A deleted menu item must not take order history with it.
alter table public.order_items drop constraint if exists order_items_menu_item_id_fkey;
alter table public.order_items
  add constraint order_items_menu_item_id_fkey
  foreign key (menu_item_id) references public.menu_items (id) on delete set null;

-- ------------------------------------------------------- old-schema leftovers --

-- Took the student id from the caller, so any signed-in user could place an
-- order in someone else's name. place_order(p_cafeteria_id, p_payment_method)
-- is the only entry point now.
drop function if exists public.place_order(uuid, uuid, jsonb);

-- Let ANY staff account read and update EVERY cafeteria's orders, bypassing
-- the is_staff_of() rule in 0006 (BR-3). Staff change orders only through
-- advance_order / cancel_order.
drop policy if exists "Staff can view all orders"       on public.orders;
drop policy if exists "Staff can update all orders"     on public.orders;
drop policy if exists "Staff can view all order items"  on public.order_items;

-- Superseded by orders_select_own_or_staff / order_items_select_via_order.
drop policy if exists "Students can view their own orders"      on public.orders;
drop policy if exists "Students can view their own order items" on public.order_items;

-- -------------------------------------------------------------- realtime --
-- The student's live status and the staff queue stream `orders`. It was
-- switched on by hand in the dashboard; recorded here so a fresh project
-- gets it too.
do $$
declare
  v_table text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    return;
  end if;

  foreach v_table in array array['orders', 'order_items'] loop
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = v_table
    ) then
      execute format('alter publication supabase_realtime add table public.%I', v_table);
    end if;
  end loop;
end;
$$;
