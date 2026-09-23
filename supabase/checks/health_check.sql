-- supabase/checks/health_check.sql
--
-- READ-ONLY. Checks that the database has everything this version of the app
-- needs. Run it in the SQL Editor after the migrations; every row should say
-- OK. A MISSING row names the migration to run.

select kind, name, status from (
with expected(kind, name, migration) as (
  values
    -- tables
    ('table',    'orders',                 '0003 / 0010'),
    ('table',    'order_items',            '0003 / 0010'),
    ('table',    'payments',               '0003'),
    ('table',    'stock_reservations',     '0003'),
    ('table',    'staff_cafeterias',       '0003'),
    ('table',    'menu_specials',          '0008'),
    ('table',    'menu_item_variants',     '0009'),
    ('table',    'combo_components',       '0009'),
    ('table',    'reservation_holds',      '0009'),
    ('table',    'user_notifications',     '0011'),
    -- columns the app reads or writes
    ('column',   'orders.payment_method',  '0010'),
    ('column',   'orders.payment_state',   '0010'),
    ('column',   'orders.total_cents',     '0010'),
    ('column',   'orders.collection_ref',  '0010'),
    ('column',   'orders.updated_at',      '0010'),
    ('column',   'order_items.name',       '0010'),
    ('column',   'order_items.unit_price_cents', '0010'),
    ('column',   'order_items.details',    '0009'),
    ('column',   'menu_items.price_cents', '0002'),
    ('column',   'menu_items.category',    '0009'),
    ('column',   'cafeterias.image_url',   '0008'),
    ('column',   'profiles.avatar_url',    '0011'),
    -- functions the app calls
    ('function', 'reserve_line',           '0009'),
    ('function', 'release_line',           '0009'),
    ('function', 'release_my_reservations','0009'),
    ('function', 'place_order',            '0009'),
    ('function', 'advance_order',          '0004'),
    ('function', 'cancel_order',           '0009'),
    ('function', 'ensure_profile',         '0011'),
    ('function', 'complete_profile',       '0006'),
    ('function', 'lookup_login_email',     '0005'),
    ('function', 'is_staff_of',            '0006'),
    -- live updates
    ('realtime', 'orders',                 '0010'),
    ('realtime', 'menu_items',             'dashboard'),
    ('realtime', 'menu_item_variants',     '0009'),
    ('realtime', 'menu_specials',          '0008'),
    ('realtime', 'combo_components',       '0009'),
    ('realtime', 'notifications',          '0011'),
    ('realtime', 'user_notifications',     '0011'),
    -- triggers that send order notifications
    ('trigger',  'orders_notify_placed',   '0011'),
    ('trigger',  'orders_notify_changed',  '0011')
)
select e.kind,
       e.name,
       case
         when e.kind = 'table' then exists (
           select 1 from information_schema.tables
            where table_schema = 'public' and table_name = e.name)
         when e.kind = 'column' then exists (
           select 1 from information_schema.columns
            where table_schema = 'public'
              and table_name = split_part(e.name, '.', 1)
              and column_name = split_part(e.name, '.', 2))
         when e.kind = 'function' then exists (
           select 1 from pg_proc
            where pronamespace = 'public'::regnamespace and proname = e.name)
         when e.kind = 'realtime' then exists (
           select 1 from pg_publication_tables
            where pubname = 'supabase_realtime'
              and schemaname = 'public' and tablename = e.name)
         when e.kind = 'trigger' then exists (
           select 1 from pg_trigger
            where tgname = e.name and not tgisinternal)
       end as present,
       case
         when e.kind = 'table' and not exists (
           select 1 from information_schema.tables
            where table_schema = 'public' and table_name = e.name)
           then 'MISSING — run ' || e.migration
         when e.kind = 'column' and not exists (
           select 1 from information_schema.columns
            where table_schema = 'public'
              and table_name = split_part(e.name, '.', 1)
              and column_name = split_part(e.name, '.', 2))
           then 'MISSING — run ' || e.migration
         when e.kind = 'function' and not exists (
           select 1 from pg_proc
            where pronamespace = 'public'::regnamespace and proname = e.name)
           then 'MISSING — run ' || e.migration
         when e.kind = 'realtime' and not exists (
           select 1 from pg_publication_tables
            where pubname = 'supabase_realtime'
              and schemaname = 'public' and tablename = e.name)
           then 'MISSING — run ' || e.migration
         when e.kind = 'trigger' and not exists (
           select 1 from pg_trigger where tgname = e.name and not tgisinternal)
           then 'MISSING — run ' || e.migration
         else 'OK'
       end as status
  from expected e

union all

-- orders.status must be the order_status enum, not the old text column.
select 'type', 'orders.status is order_status', null,
       case when exists (
         select 1 from information_schema.columns
          where table_schema = 'public' and table_name = 'orders'
            and column_name = 'status' and udt_name = 'order_status')
       then 'OK' else 'MISSING — run 0010' end

union all

-- The old place_order that trusted a client-supplied student id must be gone.
select 'security', 'old place_order(student_id, ...) removed', null,
       case when exists (
         select 1 from pg_proc
          where pronamespace = 'public'::regnamespace and proname = 'place_order'
            and pg_get_function_identity_arguments(oid) like 'p_student_id%')
       then 'STILL PRESENT — run 0010' else 'OK' end

union all

select 'data', 'staff assigned to a cafeteria', null,
       case when exists (select 1 from public.staff_cafeterias)
       then 'OK' else 'NONE — see supabase/seed/grant_staff_access.sql' end
) checks
-- Problems first.
order by (status = 'OK'), kind, name;
