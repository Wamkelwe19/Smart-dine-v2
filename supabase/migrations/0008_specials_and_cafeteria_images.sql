-- 0008_specials_and_cafeteria_images.sql
--
-- Adds:
--   * cafeterias.image_url — the cover photo on the student home page.
--   * menu_specials — discounts and featured items that staff publish.
--   * effective_price_cents() — the single definition of "what an item costs
--     right now", used by place_order so the discount is what the student is
--     actually charged, not just what the screen shows.
--
-- Idempotent: safe to run more than once.

-- ------------------------------------------------------- cafeteria photo --
alter table public.cafeterias add column if not exists image_url text;

-- --------------------------------------------------------- menu_specials --
create table if not exists public.menu_specials (
  id                  uuid primary key default gen_random_uuid(),
  menu_item_id        uuid not null references public.menu_items (id) on delete cascade,
  cafeteria_id        uuid not null references public.cafeterias (id) on delete cascade,
  kind                text not null check (kind in ('percent', 'fixed_price', 'featured')),
  percent_off         integer check (percent_off between 1 and 90),
  special_price_cents integer check (special_price_cents >= 0),
  headline            text,
  starts_at           timestamptz not null default now(),
  ends_at             timestamptz,
  is_active           boolean not null default true,
  created_by          uuid default auth.uid() references public.profiles (id) on delete set null,
  created_at          timestamptz not null default now(),

  constraint menu_specials_window check (ends_at is null or ends_at > starts_at),
  -- Each kind carries exactly the value it needs and nothing else.
  constraint menu_specials_kind_values check (
    (kind = 'percent'     and percent_off is not null and special_price_cents is null) or
    (kind = 'fixed_price' and special_price_cents is not null and percent_off is null) or
    (kind = 'featured'    and percent_off is null and special_price_cents is null)
  )
);

create index if not exists menu_specials_cafeteria_idx on public.menu_specials (cafeteria_id);
create index if not exists menu_specials_item_idx      on public.menu_specials (menu_item_id);

-- The cafeteria is derived from the item, never trusted from the client, so a
-- staff member cannot attach a special to another outlet's item by passing
-- their own cafeteria_id alongside it.
create or replace function public.menu_specials_set_cafeteria()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select cafeteria_id into new.cafeteria_id
    from public.menu_items where id = new.menu_item_id;

  if new.cafeteria_id is null then
    raise exception 'MENU_ITEM_NOT_FOUND';
  end if;

  return new;
end;
$$;

drop trigger if exists menu_specials_set_cafeteria on public.menu_specials;
create trigger menu_specials_set_cafeteria
  before insert or update of menu_item_id, cafeteria_id on public.menu_specials
  for each row execute function public.menu_specials_set_cafeteria();

-- ---------------------------------------------------- effective_price_cents --
-- The lowest of the base price and every live special. Featured specials do
-- not change the price. A fixed "special" price above the base is ignored, so
-- a special can never make an item dearer.
--
-- The rounding here must match MenuSpecial.applyTo in lib/data/models.
create or replace function public.effective_price_cents(p_item_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select least(
    m.price_cents,
    coalesce((
      select min(
        case s.kind
          when 'percent'     then round(m.price_cents * (100 - s.percent_off) / 100.0)::integer
          when 'fixed_price' then s.special_price_cents
        end
      )
        from public.menu_specials s
       where s.menu_item_id = m.id
         and s.kind <> 'featured'
         and s.is_active
         and s.starts_at <= now()
         and (s.ends_at is null or s.ends_at > now())
    ), m.price_cents)
  )
  from public.menu_items m
  where m.id = p_item_id;
$$;

revoke all on function public.effective_price_cents(uuid) from public;
grant execute on function public.effective_price_cents(uuid) to authenticated;

-- ------------------------------------------------------------- place_order --
-- Identical to 0004 except that both the total and the unit-price snapshot use
-- effective_price_cents() instead of the raw price_cents.
create or replace function public.place_order(
  p_cafeteria_id   uuid,
  p_payment_method public.payment_method
)
returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_is_open    boolean;
  v_total      integer;
  v_lines      integer;
  v_other      integer;
  v_order      public.orders;
  v_ref        text;
  v_attempts   integer := 0;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select is_open into v_is_open
    from public.cafeterias where id = p_cafeteria_id;

  if v_is_open is null then
    raise exception 'CAFETERIA_NOT_FOUND';
  end if;

  -- BR-6: an order may only be placed against an outlet open at confirmation.
  if not v_is_open then
    raise exception 'CAFETERIA_CLOSED';
  end if;

  -- REQ-53: refuse a cart spanning more than one cafeteria.
  select count(*) into v_other
    from public.stock_reservations r
    join public.menu_items m on m.id = r.menu_item_id
   where r.student_id = v_uid
     and r.order_id is null
     and m.cafeteria_id <> p_cafeteria_id;

  if v_other > 0 then
    raise exception 'CART_SPANS_CAFETERIAS';
  end if;

  select coalesce(sum(public.effective_price_cents(m.id) * r.quantity), 0), count(*)
    into v_total, v_lines
    from public.stock_reservations r
    join public.menu_items m on m.id = r.menu_item_id
   where r.student_id = v_uid
     and r.order_id is null
     and m.cafeteria_id = p_cafeteria_id;

  -- REQ-59: an empty cart cannot be checked out.
  -- Tested on the line count, not the total: a cart holding only free items
  -- also totals zero, and refusing that as "empty" would be wrong.
  if v_lines = 0 then
    raise exception 'CART_EMPTY';
  end if;

  -- Retry on the (vanishingly unlikely) collection reference collision.
  loop
    v_attempts := v_attempts + 1;
    v_ref := public.gen_collection_ref();
    begin
      insert into public.orders (
        student_id, cafeteria_id, payment_method, total_cents, collection_ref
      )
      values (v_uid, p_cafeteria_id, p_payment_method, v_total, v_ref)
      returning * into v_order;
      exit;
    exception when unique_violation then
      if v_attempts >= 5 then
        raise exception 'COLLECTION_REF_COLLISION';
      end if;
    end;
  end loop;

  -- Snapshot name and the price actually charged, special included.
  insert into public.order_items (order_id, menu_item_id, name, unit_price_cents, quantity)
  select v_order.id, m.id, m.name, public.effective_price_cents(m.id), r.quantity
    from public.stock_reservations r
    join public.menu_items m on m.id = r.menu_item_id
   where r.student_id = v_uid
     and r.order_id is null
     and m.cafeteria_id = p_cafeteria_id;

  -- Convert the reservations; they are now held by the order, not the cart, so
  -- the expiry sweep must no longer touch them.
  update public.stock_reservations r
     set order_id = v_order.id
    from public.menu_items m
   where m.id = r.menu_item_id
     and r.student_id = v_uid
     and r.order_id is null
     and m.cafeteria_id = p_cafeteria_id;

  return v_order;
end;
$$;

-- --------------------------------------------------------------------- RLS --
alter table public.menu_specials enable row level security;

drop policy if exists menu_specials_select_all on public.menu_specials;
create policy menu_specials_select_all on public.menu_specials
  for select to authenticated using (true);

-- BR-3: only staff bound to the item's cafeteria may publish or change a
-- special. cafeteria_id is set by the trigger above before this is checked.
drop policy if exists menu_specials_insert_staff on public.menu_specials;
create policy menu_specials_insert_staff on public.menu_specials
  for insert to authenticated
  with check (public.is_staff_of(cafeteria_id));

drop policy if exists menu_specials_update_staff on public.menu_specials;
create policy menu_specials_update_staff on public.menu_specials
  for update to authenticated
  using (public.is_staff_of(cafeteria_id))
  with check (public.is_staff_of(cafeteria_id));

drop policy if exists menu_specials_delete_staff on public.menu_specials;
create policy menu_specials_delete_staff on public.menu_specials
  for delete to authenticated
  using (public.is_staff_of(cafeteria_id));

-- ---------------------------------------------------------------- realtime --
-- The app streams this table; the home carousel updates when staff change it.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'menu_specials'
     ) then
    alter publication supabase_realtime add table public.menu_specials;
  end if;
end;
$$;
