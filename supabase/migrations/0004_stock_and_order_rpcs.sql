-- 0004_stock_and_order_rpcs.sql
--
-- Replaces all seven client-side stock statements with SECURITY DEFINER
-- functions. Closes REQ-50 (atomicity), REQ-51 (abandoned carts), REQ-53
-- (single-cafeteria cart), REQ-62/63/64/69 (order lifecycle) and BR-6/BR-7.
--
-- Why the client cannot do this correctly: it currently does
--     SELECT stock_count            -> 5
--     UPDATE SET stock_count = 5-1  -> 4
-- Two students who both read 5 both write 4, so two units are sold and one is
-- consumed. Every function below instead uses a single predicated UPDATE, where
-- the second caller re-evaluates `stock_count >= p_qty` against the row lock the
-- first caller holds. Exactly one succeeds. No advisory locks or explicit
-- transactions are needed: a single UPDATE statement is already atomic, and the
-- predicate is evaluated after the lock is acquired.

-- ----------------------------------------------------------- reserve_stock --
create or replace function public.reserve_stock(
  p_menu_item_id uuid,
  p_qty          integer default 1
)
returns integer                       -- remaining stock after the reservation
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_remaining integer;
  v_is_open   boolean;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if p_qty is null or p_qty <= 0 then
    raise exception 'INVALID_QUANTITY';
  end if;

  -- BR-6 / REQ-35: no reservations against a closed outlet.
  select c.is_open
    into v_is_open
    from public.menu_items m
    join public.cafeterias c on c.id = m.cafeteria_id
   where m.id = p_menu_item_id;

  if v_is_open is null then
    raise exception 'ITEM_NOT_FOUND';
  end if;

  if not v_is_open then
    raise exception 'CAFETERIA_CLOSED';
  end if;

  -- The atomic decrement. REQ-48 (re-read before increase) is satisfied
  -- implicitly: the predicate IS the read, and it happens under lock.
  update public.menu_items
     set stock_count = stock_count - p_qty
   where id = p_menu_item_id
     and is_available = true
     and stock_count >= p_qty
  returning stock_count into v_remaining;

  if not found then
    raise exception 'INSUFFICIENT_STOCK';
  end if;

  insert into public.stock_reservations (menu_item_id, student_id, quantity)
  values (p_menu_item_id, v_uid, p_qty)
  on conflict (menu_item_id, student_id) where order_id is null
  do update
     set quantity   = stock_reservations.quantity + excluded.quantity,
         expires_at = now() + interval '30 minutes';

  return v_remaining;
end;
$$;

-- ----------------------------------------------------------- release_stock --
-- REQ-47. Returns stock only up to what the caller actually holds, which closes
-- the current "press minus on a phantom cart row to mint stock" bug.
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
  v_uid       uuid := auth.uid();
  v_held      integer;
  v_release   integer;
  v_remaining integer;
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
   where menu_item_id = p_menu_item_id
     and student_id   = v_uid
     and order_id is null
   for update;

  if v_held is null then
    raise exception 'NO_RESERVATION';
  end if;

  v_release := least(p_qty, v_held);

  if v_held - v_release = 0 then
    delete from public.stock_reservations
     where menu_item_id = p_menu_item_id
       and student_id   = v_uid
       and order_id is null;
  else
    update public.stock_reservations
       set quantity = quantity - v_release
     where menu_item_id = p_menu_item_id
       and student_id   = v_uid
       and order_id is null;
  end if;

  update public.menu_items
     set stock_count = stock_count + v_release
   where id = p_menu_item_id
  returning stock_count into v_remaining;

  return v_remaining;
end;
$$;

-- ------------------------------------------------- release_my_reservations --
-- REQ-93: called on sign-out so a departing user does not strand stock.
create or replace function public.release_my_reservations()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_count integer := 0;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  with freed as (
    delete from public.stock_reservations
     where student_id = v_uid
       and order_id is null
    returning menu_item_id, quantity
  ), totals as (
    select menu_item_id, sum(quantity) as qty from freed group by menu_item_id
  ), restored as (
    update public.menu_items m
       set stock_count = m.stock_count + t.qty
      from totals t
     where m.id = t.menu_item_id
    returning 1
  )
  select count(*) into v_count from restored;

  return v_count;
end;
$$;

-- --------------------------------------------- release_expired_reservations --
-- REQ-51. Scheduled sweep; see the pg_cron registration at the end of this file.
--
-- The quantities MUST be aggregated per menu item before the update: several
-- students can hold expired reservations against the same item, and
-- `UPDATE ... FROM` applies only one matching source row per target row, so
-- summing first is what stops stock being silently under-restored.
create or replace function public.release_expired_reservations()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
begin
  with freed as (
    delete from public.stock_reservations
     where order_id is null
       and expires_at < now()
    returning menu_item_id, quantity
  ), totals as (
    select menu_item_id, sum(quantity) as qty from freed group by menu_item_id
  ), restored as (
    update public.menu_items m
       set stock_count = m.stock_count + t.qty
      from totals t
     where m.id = t.menu_item_id
    returning 1
  )
  select count(*) into v_count from restored;

  return v_count;
end;
$$;

-- ------------------------------------------------------------- place_order --
-- REQ-62/63, REQ-53, BR-6. Converts this student's open reservations for one
-- cafeteria into an order plus its line items, atomically. Stock is already
-- decremented (it was reserved), so this does not touch menu_items at all.
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

  select coalesce(sum(m.price_cents * r.quantity), 0), count(*)
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

  -- Snapshot name and unit price at order time.
  insert into public.order_items (order_id, menu_item_id, name, unit_price_cents, quantity)
  select v_order.id, m.id, m.name, m.price_cents, r.quantity
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

-- ----------------------------------------------------------- advance_order --
-- REQ-64 / BR-7: forward-only. new -> preparing -> ready -> collected.
create or replace function public.advance_order(
  p_order_id uuid,
  p_to       public.order_status
)
returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_order public.orders;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;

  if v_order.id is null then
    raise exception 'ORDER_NOT_FOUND';
  end if;

  -- BR-3: only staff bound to this order's cafeteria may move it.
  if not exists (
    select 1 from public.staff_cafeterias
     where staff_id = v_uid and cafeteria_id = v_order.cafeteria_id
  ) then
    raise exception 'NOT_AUTHORISED_FOR_CAFETERIA';
  end if;

  if not (
       (v_order.status = 'new'       and p_to = 'preparing')
    or (v_order.status = 'preparing' and p_to = 'ready')
    or (v_order.status = 'ready'     and p_to = 'collected')
  ) then
    raise exception 'ILLEGAL_TRANSITION';
  end if;

  update public.orders
     set status       = p_to,
         collected_at = case when p_to = 'collected' then now() else collected_at end,
         -- A cash order is settled at the counter on collection.
         payment_state = case
           when p_to = 'collected' and payment_method = 'cash' and payment_state = 'pending'
             then 'paid'::public.payment_state
           else payment_state
         end
   where id = p_order_id
  returning * into v_order;

  return v_order;
end;
$$;

-- ------------------------------------------------------------ cancel_order --
-- REQ-64 (cancel only from new or preparing) and REQ-69 (return the stock).
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
  v_uid     uuid := auth.uid();
  v_order   public.orders;
  v_is_staff boolean;
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

  -- REQ-69: return every reserved unit to the menu item. Aggregated for the
  -- same reason as the sweep above.
  update public.menu_items m
     set stock_count = m.stock_count + t.qty
    from (
      select menu_item_id, sum(quantity) as qty
        from public.stock_reservations
       where order_id = p_order_id
       group by menu_item_id
    ) t
   where m.id = t.menu_item_id;

  delete from public.stock_reservations where order_id = p_order_id;

  update public.orders
     set status              = 'cancelled',
         cancelled_at        = now(),
         cancellation_reason = p_reason
   where id = p_order_id
  returning * into v_order;

  return v_order;
end;
$$;

-- ------------------------------------------------------------- permissions --
revoke all on function public.reserve_stock(uuid, integer)                from public;
revoke all on function public.release_stock(uuid, integer)                from public;
revoke all on function public.release_my_reservations()                   from public;
revoke all on function public.release_expired_reservations()              from public;
revoke all on function public.place_order(uuid, public.payment_method)    from public;
revoke all on function public.advance_order(uuid, public.order_status)    from public;
revoke all on function public.cancel_order(uuid, text)                    from public;

grant execute on function public.reserve_stock(uuid, integer)             to authenticated;
grant execute on function public.release_stock(uuid, integer)             to authenticated;
grant execute on function public.release_my_reservations()                to authenticated;
grant execute on function public.place_order(uuid, public.payment_method) to authenticated;
grant execute on function public.advance_order(uuid, public.order_status) to authenticated;
grant execute on function public.cancel_order(uuid, text)                 to authenticated;
-- The sweep is server-side only; no client may call it.
grant execute on function public.release_expired_reservations()           to service_role;

-- --------------------------------------------------------------- scheduling --
-- pg_cron is available on the Supabase free tier and is the right fit here: the
-- sweep is pure SQL with no external calls, so paying for an Edge Function
-- invocation every five minutes would buy nothing.
--
-- Run this block once, in the SQL editor, as a superuser:
--
--   create extension if not exists pg_cron with schema extensions;
--   select cron.schedule(
--     'release-expired-reservations',
--     '*/5 * * * *',
--     $cron$ select public.release_expired_reservations(); $cron$
--   );
