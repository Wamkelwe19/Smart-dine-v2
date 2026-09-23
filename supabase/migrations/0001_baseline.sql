-- 0001_baseline.sql
-- Closes TBD-10: brings the existing schema under version control.
--
-- The four tables below already exist in the hosted project but were never
-- captured in the repository. This migration is written to be idempotent so it
-- can run safely against the live database (creating nothing, only filling in
-- missing constraints) or against a fresh one (creating everything).
--
-- It also normalises the nullable-boolean ambiguity the client currently papers
-- over: `is_available` was defaulted to `false` in student_home_screen.dart and
-- `true` in staff_dashboard_screen.dart, and `is_open` likewise disagreed
-- between files. Making both NOT NULL with an explicit default removes the
-- question entirely.

-- gen_random_uuid() is built into PostgreSQL 13+, so no extension is required.

-- ---------------------------------------------------------------- profiles --
create table if not exists public.profiles (
  id                uuid primary key references auth.users (id) on delete cascade,
  name              text,
  surname           text,
  student_staff_id  text,
  email             text,
  phone             text,
  role              text not null default 'student',
  created_at        timestamptz not null default now()
);

alter table public.profiles add column if not exists name             text;
alter table public.profiles add column if not exists surname          text;
alter table public.profiles add column if not exists student_staff_id text;
alter table public.profiles add column if not exists email            text;
alter table public.profiles add column if not exists phone            text;
alter table public.profiles add column if not exists role             text;
alter table public.profiles add column if not exists created_at       timestamptz not null default now();

-- Set once here so a Google account that has not completed its profile is
-- distinguishable from a fully registered one (see 0005).
alter table public.profiles add column if not exists profile_completed boolean not null default false;

update public.profiles set role = 'student' where role is null;
alter table public.profiles alter column role set default 'student';
alter table public.profiles alter column role set not null;

do $$ begin
  alter table public.profiles
    add constraint profiles_role_check check (role in ('student', 'staff'));
exception when duplicate_object then null; end $$;

-- student_staff_id is the login identifier, so it must be unique (REQ-23).
-- Partial: Google users have no number until they complete their profile.
create unique index if not exists profiles_student_staff_id_key
  on public.profiles (student_staff_id)
  where student_staff_id is not null;

-- Backfill: holding a student/staff number is what makes a profile usable, so
-- that alone marks it complete. Requiring a name as well would push existing
-- users who registered without one into the completion screen unnecessarily.
update public.profiles
   set profile_completed = true
 where profile_completed = false
   and student_staff_id is not null;

-- ------------------------------------------------------------- cafeterias --
create table if not exists public.cafeterias (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  is_open    boolean not null default false,
  created_at timestamptz not null default now()
);

update public.cafeterias set is_open = false where is_open is null;
alter table public.cafeterias alter column is_open set default false;
alter table public.cafeterias alter column is_open set not null;

-- ------------------------------------------------------------- menu_items --
create table if not exists public.menu_items (
  id           uuid primary key default gen_random_uuid(),
  cafeteria_id uuid not null references public.cafeterias (id) on delete cascade,
  name         text not null,
  price        numeric(10, 2) not null default 0,
  stock_count  integer not null default 0,
  is_available boolean not null default true,
  image_url    text,
  created_at   timestamptz not null default now()
);

update public.menu_items set is_available = true  where is_available is null;
update public.menu_items set stock_count  = 0     where stock_count  is null;
alter table public.menu_items alter column is_available set default true;
alter table public.menu_items alter column is_available set not null;
alter table public.menu_items alter column stock_count  set default 0;
alter table public.menu_items alter column stock_count  set not null;

-- REQ-74: reject negative price and stock at the database, not just the form.
do $$ begin
  alter table public.menu_items
    add constraint menu_items_stock_non_negative check (stock_count >= 0);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.menu_items
    add constraint menu_items_price_non_negative check (price >= 0);
exception when duplicate_object then null; end $$;

-- REQ-41: distinguish "sold out" from "withdrawn from sale by staff".
-- is_available is the staff switch; stock_count is the sold-out signal. The
-- client currently renders both as the single word "Unavailable".
comment on column public.menu_items.is_available is
  'Staff withdrawal switch. False = withdrawn from sale. Sold out is stock_count = 0.';

create index if not exists menu_items_cafeteria_id_idx
  on public.menu_items (cafeteria_id);

-- ---------------------------------------------------------- notifications --
create table if not exists public.notifications (
  id           uuid primary key default gen_random_uuid(),
  cafeteria_id uuid references public.cafeterias (id) on delete cascade,
  audience     text not null default 'student',
  type         text not null default 'info',
  title        text,
  message      text not null,
  metadata     jsonb,
  created_at   timestamptz not null default now()
);

do $$ begin
  alter table public.notifications
    add constraint notifications_audience_check check (audience in ('student', 'staff'));
exception when duplicate_object then null; end $$;

create index if not exists notifications_audience_created_idx
  on public.notifications (audience, created_at desc);
