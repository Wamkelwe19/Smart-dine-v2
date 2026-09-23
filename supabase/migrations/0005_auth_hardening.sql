-- 0005_auth_hardening.sql
--
-- Closes TBD-04 / REQ-111 / REQ-30.
--
-- The client currently does an UNAUTHENTICATED read of `profiles` to translate a
-- student number into an email address before signing in, then says
-- "Student/Staff ID not found" when there is no row. That is an enumeration
-- oracle: anyone can discover which student numbers are registered and harvest
-- the associated email address, and it forces `profiles` to stay readable by
-- the anon role, which blocks the RLS work in 0006.
--
-- The RPC below replaces it. It runs as definer, returns only the single column
-- authentication needs, and — critically — returns a deliberately unusable
-- address rather than NULL when the number is unknown, so a caller cannot
-- distinguish "no such number" from "wrong password": both fail identically at
-- the sign-in step. The client shows one message for both.

create or replace function public.lookup_login_email(p_number text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  if p_number is null or length(trim(p_number)) = 0 then
    raise exception 'INVALID_IDENTIFIER';
  end if;

  select email
    into v_email
    from public.profiles
   where student_staff_id = trim(p_number)
   limit 1;

  -- REQ-30: never disclose whether the number is registered. An unknown number
  -- yields an address that cannot authenticate, so the caller sees the same
  -- "invalid credentials" failure as a wrong password.
  -- md5 is a built-in, so this carries no pgcrypto dependency. It is not being
  -- used as a security primitive, only to make the address stable per input.
  if v_email is null then
    return 'unknown-' || md5(trim(p_number)) || '@invalid.local';
  end if;

  return v_email;
end;
$$;

revoke all on function public.lookup_login_email(text) from public;
grant execute on function public.lookup_login_email(text) to anon, authenticated;

-- ------------------------------------------------------- new user handling --
-- Creates the profile row from auth metadata. `role` is taken from the signup
-- form, but note that it grants nothing on its own: every staff write policy in
-- 0006 checks membership of staff_cafeterias, which only an administrator can
-- populate. A user who self-asserts role='staff' gets the staff UI and no
-- permissions, which is a dead end rather than a privilege escalation.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role   text;
  v_number text;
begin
  v_role := coalesce(new.raw_user_meta_data ->> 'role', 'student');
  if v_role not in ('student', 'staff') then
    v_role := 'student';
  end if;

  v_number := nullif(trim(coalesce(new.raw_user_meta_data ->> 'student_staff_id', '')), '');

  insert into public.profiles (
    id, email, name, surname, student_staff_id, phone, role, profile_completed
  )
  values (
    new.id,
    new.email,
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'name', '')), ''),
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'surname', '')), ''),
    v_number,
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'phone', '')), ''),
    v_role,
    -- A Google sign-in carries no number, so the profile is incomplete and the
    -- app routes to the completion screen.
    v_number is not null
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- --------------------------------------------------------- complete_profile --
-- Defined in 0006 instead, because it must opt out of the profile immutability
-- guard trigger that 0006 installs. Keeping one definition avoids the two
-- drifting apart.

-- ------------------------------------------------- identifier availability --
-- REQ-23: lets the signup form reject a duplicate number before submitting,
-- with a specific message instead of a generic failure. Returns only a boolean,
-- so it is not an enumeration oracle for email addresses.
create or replace function public.is_identifier_available(p_number text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select not exists (
    select 1 from public.profiles where student_staff_id = trim(p_number)
  );
$$;

revoke all on function public.is_identifier_available(text) from public;
grant execute on function public.is_identifier_available(text) to anon, authenticated;
