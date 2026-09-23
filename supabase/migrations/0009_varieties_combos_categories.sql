-- 0009_varieties_combos_categories.sql
--
-- Run AFTER 0008. Idempotent: safe to run more than once.
--
-- Adds:
--   * menu_items.category / description — the hall page's category tabs.
--   * menu_item_variants — varieties (flavours, sizes) with their own stock
--     and an optional price difference.
--   * combo_components — combos built from existing menu items.
--   * Cart lines that hold stock in several places at once.
--
-- The stock model. Until now one cart line held stock on exactly one menu
-- item, and every release path restored `quantity` to that item. A variety
-- holds stock on the variety; a combo holds stock on each of its parts. So a
-- cart line now records *what one unit of it holds* in reservation_holds, and
-- every release path restores `per_unit * quantity` from there. Plain items,
-- varieties and combos all go through the same code.

-- -------------------------------------------------------------- categories --
alter table public.menu_items
  add column if not exists category text not null default 'meal';
alter table public.menu_items
  add column if not exists description text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'menu_items_category_check'
  ) then
    alter table public.menu_items
      add constraint menu_items_category_check
      check (category in ('meal', 'combo', 'beverage', 'snack'));
  end if;
end;
$$;

create index if not exists menu_items_category_idx
  on public.menu_items (cafeteria_id, category);

-- --------------------------------------------------------------- varieties --
create table if not exists public.menu_item_variants (
  id                uuid primary key default gen_random_uuid(),
  menu_item_id      uuid not null references public.menu_items (id) on delete cascade,
  cafeteria_id      uuid not null references public.cafeterias (id) on delete cascade,
  name              text not null check (length(trim(name)) > 0),
  price_delta_cents integer not null default 0,
  stock_count       integer not null default 0 check (stock_count >= 0),
  is_available      boolean not null default true,
  sort_order        integer not null default 0,
  created_at        timestamptz not null default now(),
  constraint menu_item_variants_name_unique unique (menu_item_id, name)
);

create index if not exists menu_item_variants_item_idx
  on public.menu_item_variants (menu_item_id);
create index if not exists menu_item_variants_cafeteria_idx
  on public.menu_item_variants (cafeteria_id);

-- Derived from the item, never trusted from the client (same as specials).
create or replace function public.menu_item_variants_set_cafeteria()
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

drop trigger if exists menu_item_variants_set_cafeteria on public.menu_item_variants;
create trigger menu_item_variants_set_cafeteria
  before insert or update of menu_item_id, cafeteria_id on public.menu_item_variants
  for each row execute function public.menu_item_variants_set_cafeteria();

-- ------------------------------------------------------------------ combos --
create table if not exists public.combo_components (
  id                uuid primary key default gen_random_uuid(),
  combo_item_id     uuid not null references public.menu_items (id) on delete cascade,
  component_item_id uuid not null references public.menu_items (id) on delete cascade,
  cafeteria_id      uuid not null references public.cafeterias (id) on delete cascade,
  quantity          integer not null default 1 check (quantity > 0),
  sort_order        integer not null default 0,
  constraint combo_components_unique unique (combo_item_id, component_item_id),
  constraint combo_components_not_self check (combo_item_id <> component_item_id)
);

create index if not exists combo_components_combo_idx
  on public.combo_components (combo_item_id);
create index if not exists combo_components_cafeteria_idx
  on public.combo_components (cafeteria_id);

-- A part must come from the combo's own cafeteria and must not be a combo
-- itself (a combo of combos would make stock holds recursive).
create or replace function public.combo_components_validate()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_component_cafeteria uuid;
  v_component_category  text;
begin
  select cafeteria_id into new.cafeteria_id
    from public.menu_items where id = new.combo_item_id;

  select cafeteria_id, category
    into v_component_cafeteria, v_component_category
    from public.menu_items where id = new.component_item_id;

  if new.cafeteria_id is null or v_component_cafeteria is null then
    raise exception 'MENU_ITEM_NOT_FOUND';
  end if;

  if v_component_cafeteria <> new.cafeteria_id or v_component_category = 'combo' then
    raise exception 'INVALID_COMBO_COMPONENT';
  end if;

  return new;
end;
$$;

drop trigger if exists combo_components_validate on public.combo_components;
create trigger combo_components_validate
  before insert or update on public.combo_components
  for each row execute function public.combo_components_validate();

-- -------------------------------------------------------------- cart lines --
alter table public.stock_reservations
  add column if not exists variant_id uuid
    references public.menu_item_variants (id) on delete set null;
alter table public.stock_reservations
  add column if not exists selections jsonb;
alter table public.stock_reservations
  add column if not exists line_key text not null default '';

-- One open line per (student, item, choice): "Doritos, Sweet Chilli" and
-- "Doritos, Cheese" are separate lines, repeat adds of either merge.
drop index if exists public.stock_reservations_open_unique;
create unique index if not exists stock_reservations_open_line_unique
  on public.stock_reservations (student_id, menu_item_id, line_key)
  where order_id is null;

-- What ONE unit of a cart line holds. Written and read only by the functions
-- below; clients have no policy on it at all.
create table if not exists public.reservation_holds (
  reservation_id uuid not null references public.stock_reservations (id) on delete cascade,
  menu_item_id   uuid not null references public.menu_items (id) on delete cascade,
  -- A deleted variety drops its hold: there is no longer anything to restore.
  variant_id     uuid references public.menu_item_variants (id) on delete cascade,
  per_unit       integer not null check (per_unit > 0),
  constraint reservation_holds_unique
    unique nulls not distinct (reservation_id, menu_item_id, variant_id)
);

create index if not exists reservation_holds_reservation_idx
  on public.reservation_holds (reservation_id);

-- Backfill: every existing line held one unit of its own item.
insert into public.reservation_holds (reservation_id, menu_item_id, variant_id, per_unit)
select r.id, r.menu_item_id, null, 1
  from public.stock_reservations r
 where not exists (
   select 1 from public.reservation_holds h where h.reservation_id = r.id
 );

alter table public.reservation_holds enable row level security;

-- -------------------------------------------------------------- order lines --
alter table public.order_items
  add column if not exists variant_id uuid
    references public.menu_item_variants (id) on delete set null;
alter table public.order_items
  add column if not exists details text;

-- ------------------------------------------------------------------ pricing --
-- What one unit of an item costs now, for a given variety (or none).
--
-- base = price + the variety's difference. A percent special takes its
-- percentage off the whole base; a fixed special price replaces the item's
-- price and keeps the variety's difference. The lowest wins, and a special
-- never makes anything dearer. MenuItem.priceFor in the app mirrors this.
create or replace function public.effective_price_cents(
  p_item_id    uuid,
  p_variant_id uuid
)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  with base as (
    select m.id,
           m.price_cents + coalesce(v.price_delta_cents, 0) as base_cents,
           coalesce(v.price_delta_cents, 0)                 as delta_cents
      from public.menu_items m
      left join public.menu_item_variants v
        on v.id = p_variant_id and v.menu_item_id = m.id
     where m.id = p_item_id
  )
  select greatest(0, least(
    b.base_cents,
    coalesce((
      select min(
        case s.kind
          when 'percent'     then round(b.base_cents * (100 - s.percent_off) / 100.0)::integer
          when 'fixed_price' then s.special_price_cents + b.delta_cents
        end
      )
        from public.menu_specials s
       where s.menu_item_id = b.id
         and s.kind <> 'featured'
         and s.is_active
         and s.starts_at <= now()
         and (s.ends_at is null or s.ends_at > now())
    ), b.base_cents)
  ))
  from base b;
$$;

-- 0008's one-argument form, kept for anything still calling it.
create or replace function public.effective_price_cents(p_item_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select public.effective_price_cents(p_item_id, null::uuid);
$$;

-- The price of one unit of a cart line.
--   plain item / variety: effective_price_cents(item, variety)
--   combo: the combo's own effective price (it can carry a special) plus the
--          price differences of the varieties chosen for its parts.
create or replace function public.line_unit_price_cents(p_reservation_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_item     uuid;
  v_variant  uuid;
  v_category text;
  v_extra    integer;
begin
  select r.menu_item_id, r.variant_id, m.category
    into v_item, v_variant, v_category
    from public.stock_reservations r
    join public.menu_items m on m.id = r.menu_item_id
   where r.id = p_reservation_id;

  if v_item is null then
    return 0;
  end if;

  if v_category <> 'combo' then
    return public.effective_price_cents(v_item, v_variant);
  end if;

  select coalesce(sum(v.price_delta_cents * h.per_unit), 0)
    into v_extra
    from public.reservation_holds h
    join public.menu_item_variants v on v.id = h.variant_id
   where h.reservation_id = p_reservation_id;

  return greatest(0, public.effective_price_cents(v_item, null::uuid) + v_extra);
end;
$$;

-- What the kitchen needs to know about a line: "Sweet Chilli", or
-- "Burger · 2× Chips · Coke (Zero)".
create or replace function public.line_details(p_reservation_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when m.category = 'combo' then (
      select string_agg(
               case when h.per_unit > 1 then h.per_unit || '× ' else '' end
               || c.name
               || coalesce(' (' || v.name || ')', ''),
               ' · ' order by cc.sort_order, c.name)
        from public.reservation_holds h
        join public.menu_items c on c.id = h.menu_item_id
        left join public.menu_item_variants v on v.id = h.variant_id
        left join public.combo_components cc
          on cc.combo_item_id = r.menu_item_id
         and cc.component_item_id = h.menu_item_id
       where h.reservation_id = r.id
    )
    else (select v.name from public.menu_item_variants v where v.id = r.variant_id)
  end
  from public.stock_reservations r
  join public.menu_items m on m.id = r.menu_item_id
  where r.id = p_reservation_id;
$$;

-- ---------------------------------------------------------- stock restore --
-- Returns every unit the given lines hold, at their current quantities.
-- Holds are unique per (line, item, variety), and are summed across lines
-- before updating, because UPDATE ... FROM applies only one source row per
-- target row (the same trap 0004's sweep comment describes).
create or replace function public.restore_reservation_stock(p_reservation_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_reservation_ids is null or cardinality(p_reservation_ids) = 0 then
    return;
  end if;

  update public.menu_items m
     set stock_count = m.stock_count + t.qty
    from (
      select h.menu_item_id, sum(h.per_unit * r.quantity) as qty
        from public.reservation_holds h
        join public.stock_reservations r on r.id = h.reservation_id
       where r.id = any (p_reservation_ids)
         and h.variant_id is null
       group by h.menu_item_id
    ) t
   where m.id = t.menu_item_id;

  update public.menu_item_variants v
     set stock_count = v.stock_count + t.qty
    from (
      select h.variant_id, sum(h.per_unit * r.quantity) as qty
        from public.reservation_holds h
        join public.stock_reservations r on r.id = h.reservation_id
       where r.id = any (p_reservation_ids)
         and h.variant_id is not null
       group by h.variant_id
    ) t
   where v.id = t.variant_id;
end;
$$;

revoke all on function public.restore_reservation_stock(uuid[]) from public, anon, authenticated;

-- ------------------------------------------------------------ reserve_line --
-- Adds p_qty units of one choice of an item to the caller's cart.
--
--   plain item:  p_variant_id and p_selections null
--   variety:     p_variant_id = the chosen variety
--   combo:       p_selections = [{"component_item_id": ..., "variant_id": ...}]
--                for every part that has varieties
--
-- Every stock decrement is a single predicated UPDATE, as in 0004. If any one
-- of them comes up short the function raises, and the whole call — including
-- decrements already made for other parts — rolls back.
create or replace function public.reserve_line(
  p_menu_item_id uuid,
  p_variant_id   uuid    default null,
  p_selections   jsonb   default null,
  p_qty          integer default 1
)
returns uuid                          -- the cart line's id
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_is_open   boolean;
  v_on_sale   boolean;
  v_category  text;
  v_holds     jsonb := '[]'::jsonb;
  v_line_key  text  := '';
  v_line_id   uuid;
  v_component record;
  v_choice    uuid;
  v_hold      record;
  v_need      integer;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if p_qty is null or p_qty <= 0 then
    raise exception 'INVALID_QUANTITY';
  end if;

  select c.is_open, m.is_available, m.category
    into v_is_open, v_on_sale, v_category
    from public.menu_items m
    join public.cafeterias c on c.id = m.cafeteria_id
   where m.id = p_menu_item_id;

  if v_is_open is null then
    raise exception 'ITEM_NOT_FOUND';
  end if;

  -- BR-6 / REQ-35: no reservations against a closed outlet.
  if not v_is_open then
    raise exception 'CAFETERIA_CLOSED';
  end if;

  if not v_on_sale then
    raise exception 'INSUFFICIENT_STOCK';
  end if;

  if v_category = 'combo' then
    if p_variant_id is not null then
      raise exception 'INVALID_SELECTION';
    end if;

    for v_component in
      select cc.component_item_id, cc.quantity,
             exists (
               select 1 from public.menu_item_variants v
                where v.menu_item_id = cc.component_item_id
             ) as has_variants
        from public.combo_components cc
       where cc.combo_item_id = p_menu_item_id
       order by cc.component_item_id
    loop
      v_choice := null;

      if v_component.has_variants then
        select (e ->> 'variant_id')::uuid
          into v_choice
          from jsonb_array_elements(coalesce(p_selections, '[]'::jsonb)) e
         where (e ->> 'component_item_id')::uuid = v_component.component_item_id
         limit 1;

        if v_choice is null or not exists (
          select 1 from public.menu_item_variants v
           where v.id = v_choice
             and v.menu_item_id = v_component.component_item_id
        ) then
          raise exception 'SELECTION_REQUIRED';
        end if;
      end if;

      v_holds := v_holds || jsonb_build_object(
        'menu_item_id', v_component.component_item_id,
        'variant_id',   v_choice,
        'per_unit',     v_component.quantity
      );
      v_line_key := v_line_key
        || v_component.component_item_id::text || ':'
        || coalesce(v_choice::text, '') || ';';
    end loop;

    if jsonb_array_length(v_holds) = 0 then
      raise exception 'COMBO_EMPTY';
    end if;
  elsif exists (
    select 1 from public.menu_item_variants v where v.menu_item_id = p_menu_item_id
  ) then
    if p_variant_id is null then
      raise exception 'SELECTION_REQUIRED';
    end if;

    if not exists (
      select 1 from public.menu_item_variants v
       where v.id = p_variant_id and v.menu_item_id = p_menu_item_id
    ) then
      raise exception 'INVALID_SELECTION';
    end if;

    v_holds := jsonb_build_array(jsonb_build_object(
      'menu_item_id', p_menu_item_id,
      'variant_id',   p_variant_id,
      'per_unit',     1
    ));
    v_line_key := p_variant_id::text;
  else
    if p_variant_id is not null then
      raise exception 'INVALID_SELECTION';
    end if;

    v_holds := jsonb_build_array(jsonb_build_object(
      'menu_item_id', p_menu_item_id,
      'variant_id',   null,
      'per_unit',     1
    ));
  end if;

  -- Take the stock. Parts are summed first in case the same one appears twice.
  for v_hold in
    select x.menu_item_id, x.variant_id, sum(x.per_unit)::integer as per_unit
      from jsonb_to_recordset(v_holds)
             as x(menu_item_id uuid, variant_id uuid, per_unit integer)
     group by x.menu_item_id, x.variant_id
  loop
    v_need := v_hold.per_unit * p_qty;

    if v_hold.variant_id is null then
      update public.menu_items
         set stock_count = stock_count - v_need
       where id = v_hold.menu_item_id
         and is_available = true
         and stock_count >= v_need;
    else
      update public.menu_item_variants v
         set stock_count = v.stock_count - v_need
       where v.id = v_hold.variant_id
         and v.is_available = true
         and v.stock_count >= v_need
         and exists (
           select 1 from public.menu_items m
            where m.id = v_hold.menu_item_id and m.is_available = true
         );
    end if;

    if not found then
      raise exception 'INSUFFICIENT_STOCK';
    end if;
  end loop;

  insert into public.stock_reservations (
    menu_item_id, student_id, quantity, variant_id, selections, line_key
  )
  values (
    p_menu_item_id, v_uid, p_qty,
    case when v_category = 'combo' then null else p_variant_id end,
    case when v_category = 'combo' then p_selections else null end,
    v_line_key
  )
  on conflict (student_id, menu_item_id, line_key) where order_id is null
  do update
     set quantity   = stock_reservations.quantity + excluded.quantity,
         expires_at = now() + interval '30 minutes'
  returning id into v_line_id;

  -- Holds describe one unit, so an existing line already has the right ones.
  insert into public.reservation_holds (reservation_id, menu_item_id, variant_id, per_unit)
  select v_line_id, x.menu_item_id, x.variant_id, sum(x.per_unit)::integer
    from jsonb_to_recordset(v_holds)
           as x(menu_item_id uuid, variant_id uuid, per_unit integer)
   group by x.menu_item_id, x.variant_id
  on conflict on constraint reservation_holds_unique do nothing;

  return v_line_id;
end;
$$;

-- ------------------------------------------------------------ release_line --
-- REQ-47. Returns stock only up to what the caller's own open line holds.
create or replace function public.release_line(
  p_reservation_id uuid,
  p_qty            integer default 1
)
returns integer                       -- units left on the line
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_held    integer;
  v_release integer;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if p_qty is null or p_qty <= 0 then
    raise exception 'INVALID_QUANTITY';
  end if;

  select quantity
    into v_held
    from public.stock_reservations
   where id = p_reservation_id
     and student_id = v_uid
     and order_id is null
   for update;

  if v_held is null then
    raise exception 'NO_RESERVATION';
  end if;

  v_release := least(p_qty, v_held);

  update public.menu_items m
     set stock_count = m.stock_count + h.per_unit * v_release
    from public.reservation_holds h
   where h.reservation_id = p_reservation_id
     and h.variant_id is null
     and m.id = h.menu_item_id;

  update public.menu_item_variants v
     set stock_count = v.stock_count + h.per_unit * v_release
    from public.reservation_holds h
   where h.reservation_id = p_reservation_id
     and h.variant_id is not null
     and v.id = h.variant_id;

  if v_held - v_release = 0 then
    delete from public.stock_reservations where id = p_reservation_id;
    return 0;
  end if;

  update public.stock_reservations
     set quantity   = quantity - v_release,
         expires_at = now() + interval '30 minutes'
   where id = p_reservation_id;

  return v_held - v_release;
end;
$$;

-- ------------------------------------------- 0004 entry points, re-plumbed --
-- Older builds of the app still call these; they act on the plain-item line.
create or replace function public.reserve_stock(
  p_menu_item_id uuid,
  p_qty          integer default 1
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_remaining integer;
begin
  perform public.reserve_line(p_menu_item_id, null, null, p_qty);
  select stock_count into v_remaining from public.menu_items where id = p_menu_item_id;
  return v_remaining;
end;
$$;

create or replace function public.release_stock(
  p_menu_item_id uuid,
  p_qty          integer default 1
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line_id   uuid;
  v_remaining integer;
begin
  select id into v_line_id
    from public.stock_reservations
   where menu_item_id = p_menu_item_id
     and student_id = auth.uid()
     and order_id is null
     and line_key = '';

  if v_line_id is null then
    raise exception 'NO_RESERVATION';
  end if;

  perform public.release_line(v_line_id, p_qty);
  select stock_count into v_remaining from public.menu_items where id = p_menu_item_id;
  return v_remaining;
end;
$$;

-- REQ-93: called on sign-out so a departing user does not strand stock.
create or replace function public.release_my_reservations()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_ids uuid[];
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select coalesce(array_agg(id), '{}') into v_ids
    from (
      select id from public.stock_reservations
       where student_id = v_uid and order_id is null
       for update
    ) locked;

  perform public.restore_reservation_stock(v_ids);
  delete from public.stock_reservations where id = any (v_ids);

  return cardinality(v_ids);
end;
$$;

-- REQ-51. Scheduled sweep of abandoned carts.
create or replace function public.release_expired_reservations()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ids uuid[];
begin
  select coalesce(array_agg(id), '{}') into v_ids
    from (
      select id from public.stock_reservations
       where order_id is null and expires_at < now()
       for update skip locked
    ) locked;

  perform public.restore_reservation_stock(v_ids);
  delete from public.stock_reservations where id = any (v_ids);

  return cardinality(v_ids);
end;
$$;

-- REQ-69 / BR-7: as 0004, but stock comes back through the holds.
create or replace function public.cancel_order(
  p_order_id uuid,
  p_reason   text default null
)
returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_order    public.orders;
  v_is_staff boolean;
  v_ids      uuid[];
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;

  if v_order.id is null then
    raise exception 'ORDER_NOT_FOUND';
  end if;

  select exists (
    select 1 from public.staff_cafeterias
     where staff_id = v_uid and cafeteria_id = v_order.cafeteria_id
  ) into v_is_staff;

  -- The owning student or bound staff may cancel; nobody else.
  if v_order.student_id <> v_uid and not v_is_staff then
    raise exception 'NOT_AUTHORISED';
  end if;

  if v_order.status not in ('new', 'preparing') then
    raise exception 'ILLEGAL_TRANSITION';
  end if;

  select coalesce(array_agg(id), '{}') into v_ids
    from public.stock_reservations where order_id = p_order_id;

  perform public.restore_reservation_stock(v_ids);
  delete from public.stock_reservations where id = any (v_ids);

  update public.orders
     set status              = 'cancelled',
         cancelled_at        = now(),
         cancellation_reason = p_reason
   where id = p_order_id
  returning * into v_order;

  return v_order;
end;
$$;

-- ------------------------------------------------------------- place_order --
-- As 0008, but each line is priced by line_unit_price_cents() and the order
-- line keeps which variety / combo parts were chosen.
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

  select coalesce(sum(public.line_unit_price_cents(r.id) * r.quantity), 0), count(*)
    into v_total, v_lines
    from public.stock_reservations r
    join public.menu_items m on m.id = r.menu_item_id
   where r.student_id = v_uid
     and r.order_id is null
     and m.cafeteria_id = p_cafeteria_id;

  -- REQ-59: tested on the line count, not the total (free items total zero).
  if v_lines = 0 then
    raise exception 'CART_EMPTY';
  end if;

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

  -- Snapshot the name, the price actually charged, and what was chosen.
  insert into public.order_items (
    order_id, menu_item_id, variant_id, name, details, unit_price_cents, quantity
  )
  select v_order.id, m.id, r.variant_id, m.name,
         public.line_details(r.id),
         public.line_unit_price_cents(r.id),
         r.quantity
    from public.stock_reservations r
    join public.menu_items m on m.id = r.menu_item_id
   where r.student_id = v_uid
     and r.order_id is null
     and m.cafeteria_id = p_cafeteria_id;

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

-- ------------------------------------------------------------------ grants --
revoke all on function public.reserve_line(uuid, uuid, jsonb, integer) from public;
revoke all on function public.release_line(uuid, integer)               from public;
revoke all on function public.effective_price_cents(uuid, uuid)         from public;
revoke all on function public.line_unit_price_cents(uuid)               from public;
revoke all on function public.line_details(uuid)                        from public;

grant execute on function public.reserve_line(uuid, uuid, jsonb, integer) to authenticated;
grant execute on function public.release_line(uuid, integer)              to authenticated;
grant execute on function public.effective_price_cents(uuid, uuid)        to authenticated;
grant execute on function public.line_unit_price_cents(uuid)              to authenticated;
grant execute on function public.line_details(uuid)                       to authenticated;

-- --------------------------------------------------------------------- RLS --
alter table public.menu_item_variants enable row level security;
alter table public.combo_components   enable row level security;

drop policy if exists menu_item_variants_select_all on public.menu_item_variants;
create policy menu_item_variants_select_all on public.menu_item_variants
  for select to authenticated using (true);

-- BR-3: cafeteria_id is set by the trigger before these are checked.
drop policy if exists menu_item_variants_insert_staff on public.menu_item_variants;
create policy menu_item_variants_insert_staff on public.menu_item_variants
  for insert to authenticated with check (public.is_staff_of(cafeteria_id));

drop policy if exists menu_item_variants_update_staff on public.menu_item_variants;
create policy menu_item_variants_update_staff on public.menu_item_variants
  for update to authenticated
  using (public.is_staff_of(cafeteria_id))
  with check (public.is_staff_of(cafeteria_id));

drop policy if exists menu_item_variants_delete_staff on public.menu_item_variants;
create policy menu_item_variants_delete_staff on public.menu_item_variants
  for delete to authenticated using (public.is_staff_of(cafeteria_id));

drop policy if exists combo_components_select_all on public.combo_components;
create policy combo_components_select_all on public.combo_components
  for select to authenticated using (true);

drop policy if exists combo_components_insert_staff on public.combo_components;
create policy combo_components_insert_staff on public.combo_components
  for insert to authenticated with check (public.is_staff_of(cafeteria_id));

drop policy if exists combo_components_update_staff on public.combo_components;
create policy combo_components_update_staff on public.combo_components
  for update to authenticated
  using (public.is_staff_of(cafeteria_id))
  with check (public.is_staff_of(cafeteria_id));

drop policy if exists combo_components_delete_staff on public.combo_components;
create policy combo_components_delete_staff on public.combo_components
  for delete to authenticated using (public.is_staff_of(cafeteria_id));

-- ---------------------------------------------------------------- realtime --
do $$
declare
  v_table text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    return;
  end if;

  foreach v_table in array array['menu_item_variants', 'combo_components'] loop
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
