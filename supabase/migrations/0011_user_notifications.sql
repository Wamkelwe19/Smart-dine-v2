-- 0011_user_notifications.sql
--
-- Run AFTER 0010. Idempotent: safe to run more than once.
--
-- Adds:
--   * user_notifications — a notice addressed to ONE person ("Your order
--     K7P2QX is ready"), written by the database whenever an order moves, and
--     streamed to the app, which shows it as a phone notification.
--     (The existing `notifications` table can only address a whole role.)
--   * profiles.avatar_url and a Google-aware new-user trigger, so an account
--     created with Google arrives with first name, surname, email and photo.
--   * ensure_profile() — creates a missing profile row for the caller instead
--     of the app signing them out.

-- 0011 builds on the order columns that 0010 adds. Stop with a clear message
-- (rather than 'column "payment_state" does not exist') if 0010 has not run.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'orders'
       and column_name = 'payment_state'
  ) then
    raise exception 'Run 0010_repair_orders.sql first, then run this file again.';
  end if;
end;
$$;

-- ------------------------------------------------------------ profiles --
alter table public.profiles add column if not exists avatar_url text;

-- One definition of "a profile from sign-in details", used by the new-user
-- trigger and by ensure_profile().
--
-- Sign-up by number sends name / surname / student_staff_id / phone / role.
-- Google sends full_name (and sometimes given_name / family_name), email,
-- avatar_url or picture — and no number, so the profile starts incomplete and
-- the app shows "Finish setting up".
create or replace function public.create_profile_from_auth(
  p_id    uuid,
  p_email text,
  p_meta  jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_meta   jsonb := coalesce(p_meta, '{}'::jsonb);
  v_role   text;
  v_number text;
  v_full   text;
  v_first  text;
  v_last   text;
  v_avatar text;
begin
  v_role := coalesce(v_meta ->> 'role', 'student');
  if v_role not in ('student', 'staff') then
    v_role := 'student';
  end if;

  v_number := nullif(trim(coalesce(v_meta ->> 'student_staff_id', '')), '');
  v_full   := nullif(trim(coalesce(v_meta ->> 'full_name', '')), '');

  -- A Google full_name is split; the sign-up form's `name` is already a
  -- first name.
  v_first := coalesce(
    nullif(trim(coalesce(v_meta ->> 'given_name', '')), ''),
    case when v_full is not null then split_part(v_full, ' ', 1) end,
    nullif(trim(coalesce(v_meta ->> 'name', '')), '')
  );
  v_last := coalesce(
    nullif(trim(coalesce(v_meta ->> 'surname', '')), ''),
    nullif(trim(coalesce(v_meta ->> 'family_name', '')), ''),
    case when v_full is not null and position(' ' in v_full) > 0
         then nullif(trim(substr(v_full, position(' ' in v_full) + 1)), '')
    end
  );
  v_avatar := coalesce(
    nullif(trim(coalesce(v_meta ->> 'avatar_url', '')), ''),
    nullif(trim(coalesce(v_meta ->> 'picture', '')), '')
  );

  insert into public.profiles (
    id, email, name, surname, student_staff_id, phone, role,
    profile_completed, avatar_url
  )
  values (
    p_id,
    p_email,
    v_first,
    v_last,
    v_number,
    nullif(trim(coalesce(v_meta ->> 'phone', '')), ''),
    v_role,
    v_number is not null,
    v_avatar
  )
  on conflict (id) do nothing;
end;
$$;

revoke all on function public.create_profile_from_auth(uuid, text, jsonb)
  from public, anon, authenticated;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.create_profile_from_auth(new.id, new.email, new.raw_user_meta_data);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Creates the caller's profile if the trigger never did (an account older
-- than the trigger, or a failed insert), and fills in the photo and email on
-- an existing row that lacks them. Never overwrites anything already set.
create or replace function public.ensure_profile()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_email text;
  v_meta  jsonb;
  v_found boolean;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select true, u.email, u.raw_user_meta_data
    into v_found, v_email, v_meta
    from auth.users u
   where u.id = v_uid;

  if not coalesce(v_found, false) then
    raise exception 'AUTH_REQUIRED';
  end if;

  perform public.create_profile_from_auth(v_uid, v_email, v_meta);

  update public.profiles p
     set avatar_url = coalesce(
           p.avatar_url,
           nullif(v_meta ->> 'avatar_url', ''),
           nullif(v_meta ->> 'picture', '')
         ),
         email = coalesce(p.email, v_email)
   where p.id = v_uid;
end;
$$;

revoke all on function public.ensure_profile() from public;
grant execute on function public.ensure_profile() to authenticated;

-- ------------------------------------------------------ user_notifications --
create table if not exists public.user_notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  order_id   uuid references public.orders (id) on delete cascade,
  kind       text not null,
  title      text not null,
  body       text not null,
  created_at timestamptz not null default now(),
  read_at    timestamptz
);

create index if not exists user_notifications_user_idx
  on public.user_notifications (user_id, created_at desc);

alter table public.user_notifications enable row level security;

drop policy if exists user_notifications_select_own on public.user_notifications;
create policy user_notifications_select_own on public.user_notifications
  for select to authenticated using (user_id = auth.uid());

drop policy if exists user_notifications_update_own on public.user_notifications;
create policy user_notifications_update_own on public.user_notifications
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Clients may only mark their own notices read; the text is the database's.
revoke insert, update, delete on public.user_notifications from anon, authenticated;
grant select on public.user_notifications to authenticated;
grant update (read_at) on public.user_notifications to authenticated;

-- --------------------------------------------------------- order notices --
create or replace function public.notify_user(
  p_user   uuid,
  p_order  uuid,
  p_kind   text,
  p_title  text,
  p_body   text
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.user_notifications (user_id, order_id, kind, title, body)
  values (p_user, p_order, p_kind, p_title, p_body);
$$;

revoke all on function public.notify_user(uuid, uuid, text, text, text)
  from public, anon, authenticated;

-- "R 45.00"
create or replace function public.format_rand(p_cents integer)
returns text
language sql
immutable
as $$
  select 'R ' || to_char(coalesce(p_cents, 0) / 100.0, 'FM999999990.00');
$$;

-- A new order, once its lines exist. Runs at COMMIT (deferred): place_order
-- inserts the order before its order_items, so a plain AFTER INSERT trigger
-- would count zero items.
create or replace function public.orders_notify_placed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hall   text;
  v_items  integer;
  v_how    text;
  v_staff  uuid;
begin
  select name into v_hall from public.cafeterias where id = new.cafeteria_id;
  select coalesce(sum(quantity), 0) into v_items
    from public.order_items where order_id = new.id;

  v_how := case new.payment_method
             when 'card' then 'card'
             else 'cash on collection'
           end;

  perform public.notify_user(
    new.student_id, new.id, 'order_placed',
    'Order ' || new.collection_ref || ' placed',
    v_items || case when v_items = 1 then ' item' else ' items' end
      || ' · ' || public.format_rand(new.total_cents)
      || ' at ' || coalesce(v_hall, 'the cafeteria')
      || '. We will let you know when it is being prepared.'
  );

  for v_staff in
    select staff_id from public.staff_cafeterias where cafeteria_id = new.cafeteria_id
  loop
    perform public.notify_user(
      v_staff, new.id, 'new_order',
      'New order ' || new.collection_ref,
      v_items || case when v_items = 1 then ' item' else ' items' end
        || ' · ' || public.format_rand(new.total_cents) || ' · ' || v_how
    );
  end loop;

  return null;
end;
$$;

drop trigger if exists orders_notify_placed on public.orders;
create constraint trigger orders_notify_placed
  after insert on public.orders
  deferrable initially deferred
  for each row execute function public.orders_notify_placed();

-- Every later step: status moves and payment results.
create or replace function public.orders_notify_changed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hall  text;
  v_ref   text := new.collection_ref;
  v_staff uuid;
begin
  select name into v_hall from public.cafeterias where id = new.cafeteria_id;

  if new.status is distinct from old.status then
    case new.status
      when 'preparing' then
        perform public.notify_user(new.student_id, new.id, 'order_preparing',
          'Order ' || v_ref || ' is being prepared',
          coalesce(v_hall, 'The cafeteria') || ' has started on your order.');
      when 'ready' then
        perform public.notify_user(new.student_id, new.id, 'order_ready',
          'Order ' || v_ref || ' is ready!',
          'Collect it at ' || coalesce(v_hall, 'the counter')
            || case when new.payment_state = 'paid' then '.'
                    else ' and pay ' || public.format_rand(new.total_cents) || ' there.'
               end);
      when 'collected' then
        perform public.notify_user(new.student_id, new.id, 'order_collected',
          'Order ' || v_ref || ' collected',
          'Enjoy your meal! Thanks for ordering with UMP Smart Dine.');
      when 'cancelled' then
        perform public.notify_user(new.student_id, new.id, 'order_cancelled',
          'Order ' || v_ref || ' was cancelled',
          coalesce('Reason: ' || nullif(trim(new.cancellation_reason), ''),
                   'The items have gone back on the menu.'));
        -- Staff hear about cancellations they did not make themselves.
        if auth.uid() is null or auth.uid() = new.student_id then
          for v_staff in
            select staff_id from public.staff_cafeterias
             where cafeteria_id = new.cafeteria_id
          loop
            perform public.notify_user(v_staff, new.id, 'order_cancelled',
              'Order ' || v_ref || ' was cancelled',
              'The student cancelled it. Its items are back on the menu.');
          end loop;
        end if;
      else
        null;
    end case;
  end if;

  -- Payment results. A cash order becomes paid in the same update that
  -- collects it; "collected" already says everything, so no second notice.
  if new.payment_state is distinct from old.payment_state
     and not (new.status = 'collected' and old.status is distinct from 'collected') then
    if new.payment_state = 'paid' then
      perform public.notify_user(new.student_id, new.id, 'payment_received',
        'Payment received for ' || v_ref,
        public.format_rand(new.total_cents) || ' paid by card. Show ' || v_ref
          || ' when you collect.');
    elsif new.payment_state = 'failed' then
      perform public.notify_user(new.student_id, new.id, 'payment_failed',
        'Card payment for ' || v_ref || ' did not go through',
        'Your order still stands. Try again from Orders, or pay at the counter.');
    end if;
  end if;

  return null;
end;
$$;

drop trigger if exists orders_notify_changed on public.orders;
create trigger orders_notify_changed
  after update of status, payment_state on public.orders
  for each row execute function public.orders_notify_changed();

-- ---------------------------------------------------------------- realtime --
-- The app streams these: its own notices, the role announcements, and orders.
do $$
declare
  v_table text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    return;
  end if;

  foreach v_table in array array['user_notifications', 'notifications', 'orders'] loop
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
