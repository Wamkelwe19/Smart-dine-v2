-- 0006_rls.sql
--
-- Closes TBD-03 / REQ-110 / REQ-76 / BR-2 / BR-3.
--
-- Until this runs, RLS is off on every table, which means any authenticated
-- user can call the REST API directly and edit any menu item at any cafeteria,
-- including its price. The publishable key is in the compiled binary, so this
-- is exploitable by anyone with the APK, not just by a developer.
--
-- The model:
--   * students read menu, cafeteria and notification data; they never write to
--     menu_items directly (BR-2) — stock moves only through the SECURITY DEFINER
--     functions in 0004, which bypass these policies by design.
--   * staff write only rows belonging to a cafeteria they are bound to through
--     staff_cafeterias (BR-3).
--   * payments are written only by the Edge Functions, which use the service
--     role and therefore bypass RLS.

-- Helper: is the current user bound to this cafeteria?
create or replace function public.is_staff_of(p_cafeteria_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.staff_cafeterias
     where staff_id = auth.uid()
       and cafeteria_id = p_cafeteria_id
  );
$$;

grant execute on function public.is_staff_of(uuid) to authenticated;

alter table public.profiles           enable row level security;
alter table public.cafeterias         enable row level security;
alter table public.menu_items         enable row level security;
alter table public.notifications      enable row level security;
alter table public.orders             enable row level security;
alter table public.order_items        enable row level security;
alter table public.payments           enable row level security;
alter table public.stock_reservations enable row level security;
alter table public.staff_cafeterias   enable row level security;

-- ---------------------------------------------------------------- profiles --
-- No anon access at all: the sign-in lookup now goes through
-- lookup_login_email(), which is definer and bypasses this.
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select to authenticated
  using (id = auth.uid());

-- Staff can see the name of a student whose order they are serving.
drop policy if exists profiles_select_customer on public.profiles;
create policy profiles_select_customer on public.profiles
  for select to authenticated
  using (
    exists (
      select 1 from public.orders o
       where o.student_id = public.profiles.id
         and public.is_staff_of(o.cafeteria_id)
    )
  );

-- Contact details are editable; role and student_staff_id are not (BR-1).
-- Those move only through complete_profile().
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create or replace function public.guard_profile_immutables()
returns trigger
language plpgsql
as $$
begin
  -- Definer functions set this to allow the one legitimate change.
  if current_setting('app.allow_profile_role_change', true) = 'on' then
    return new;
  end if;
  if new.role is distinct from old.role then
    raise exception 'ROLE_IS_IMMUTABLE';
  end if;
  if old.student_staff_id is not null
     and new.student_staff_id is distinct from old.student_staff_id then
    raise exception 'IDENTIFIER_IS_IMMUTABLE';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_guard_immutables on public.profiles;
create trigger profiles_guard_immutables
  before update on public.profiles
  for each row execute function public.guard_profile_immutables();

-- complete_profile() legitimately sets role once, so it opts out of the guard.
create or replace function public.complete_profile(
  p_role text, p_number text, p_name text, p_surname text, p_phone text
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles;
  v_done boolean;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_role not in ('student', 'staff') then raise exception 'INVALID_ROLE'; end if;
  if p_number is null or length(trim(p_number)) = 0 then
    raise exception 'INVALID_IDENTIFIER';
  end if;

  select profile_completed into v_done from public.profiles where id = v_uid;
  if v_done then raise exception 'PROFILE_ALREADY_COMPLETE'; end if;

  if exists (
    select 1 from public.profiles
     where student_staff_id = trim(p_number) and id <> v_uid
  ) then
    raise exception 'IDENTIFIER_ALREADY_REGISTERED';
  end if;

  perform set_config('app.allow_profile_role_change', 'on', true);

  update public.profiles
     set role              = p_role,
         student_staff_id  = trim(p_number),
         name              = nullif(trim(coalesce(p_name, '')), ''),
         surname           = nullif(trim(coalesce(p_surname, '')), ''),
         phone             = nullif(trim(coalesce(p_phone, '')), ''),
         profile_completed = true
   where id = v_uid
  returning * into v_profile;

  perform set_config('app.allow_profile_role_change', 'off', true);

  return v_profile;
end;
$$;

grant execute on function public.complete_profile(text, text, text, text, text) to authenticated;

-- -------------------------------------------------------------- cafeterias --
drop policy if exists cafeterias_select_all on public.cafeterias;
create policy cafeterias_select_all on public.cafeterias
  for select to authenticated using (true);

-- REQ-36 / BR-3: a staff member may change the trading status only of a
-- cafeteria they are bound to. Today the dropdown lets them pick any outlet.
drop policy if exists cafeterias_update_own on public.cafeterias;
create policy cafeterias_update_own on public.cafeterias
  for update to authenticated
  using (public.is_staff_of(id))
  with check (public.is_staff_of(id));

-- -------------------------------------------------------------- menu_items --
drop policy if exists menu_items_select_all on public.menu_items;
create policy menu_items_select_all on public.menu_items
  for select to authenticated using (true);

-- BR-2 / REQ-76: only bound staff may create, amend or delete a menu item.
-- Students never write here; stock moves through reserve_stock/release_stock.
drop policy if exists menu_items_insert_staff on public.menu_items;
create policy menu_items_insert_staff on public.menu_items
  for insert to authenticated
  with check (public.is_staff_of(cafeteria_id));

drop policy if exists menu_items_update_staff on public.menu_items;
create policy menu_items_update_staff on public.menu_items
  for update to authenticated
  using (public.is_staff_of(cafeteria_id))
  with check (public.is_staff_of(cafeteria_id));

drop policy if exists menu_items_delete_staff on public.menu_items;
create policy menu_items_delete_staff on public.menu_items
  for delete to authenticated
  using (public.is_staff_of(cafeteria_id));

-- ----------------------------------------------------------- notifications --
-- REQ-85: a user sees notices addressed to their own role.
drop policy if exists notifications_select_audience on public.notifications;
create policy notifications_select_audience on public.notifications
  for select to authenticated
  using (
    audience = (select role from public.profiles where id = auth.uid())
  );

-- REQ-89: the staff notice composer.
drop policy if exists notifications_insert_staff on public.notifications;
create policy notifications_insert_staff on public.notifications
  for insert to authenticated
  with check (cafeteria_id is not null and public.is_staff_of(cafeteria_id));

drop policy if exists notifications_delete_staff on public.notifications;
create policy notifications_delete_staff on public.notifications
  for delete to authenticated
  using (cafeteria_id is not null and public.is_staff_of(cafeteria_id));

-- ------------------------------------------------------------------ orders --
-- REQ-68 (a student sees their own) and REQ-65 (staff see only their outlet's).
drop policy if exists orders_select_own_or_staff on public.orders;
create policy orders_select_own_or_staff on public.orders
  for select to authenticated
  using (student_id = auth.uid() or public.is_staff_of(cafeteria_id));

-- Writes go exclusively through place_order / advance_order / cancel_order.
-- No insert or update policy exists, so a direct REST write is refused.

-- ------------------------------------------------------------- order_items --
drop policy if exists order_items_select_via_order on public.order_items;
create policy order_items_select_via_order on public.order_items
  for select to authenticated
  using (
    exists (
      select 1 from public.orders o
       where o.id = order_items.order_id
         and (o.student_id = auth.uid() or public.is_staff_of(o.cafeteria_id))
    )
  );

-- ---------------------------------------------------------------- payments --
-- Readable by the paying student and the serving staff; written only by the
-- Edge Functions via the service role, which bypasses RLS.
drop policy if exists payments_select_via_order on public.payments;
create policy payments_select_via_order on public.payments
  for select to authenticated
  using (
    exists (
      select 1 from public.orders o
       where o.id = payments.order_id
         and (o.student_id = auth.uid() or public.is_staff_of(o.cafeteria_id))
    )
  );

-- ------------------------------------------------------ stock_reservations --
drop policy if exists reservations_select_own on public.stock_reservations;
create policy reservations_select_own on public.stock_reservations
  for select to authenticated
  using (student_id = auth.uid());

-- Writes go through reserve_stock / release_stock only.

-- -------------------------------------------------------- staff_cafeterias --
drop policy if exists staff_cafeterias_select_own on public.staff_cafeterias;
create policy staff_cafeterias_select_own on public.staff_cafeterias
  for select to authenticated
  using (staff_id = auth.uid());

-- Granting a binding is an administrative act performed in the dashboard.
-- No insert, update or delete policy exists for any client role.
