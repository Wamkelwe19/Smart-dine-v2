-- supabase/seed/grant_staff_access.sql
--
-- Assigns a staff account to a cafeteria. Until this is done, a staff member
-- can sign in but sees "No cafeteria assigned yet" and cannot manage a menu,
-- advance orders or receive "New order" notifications. That is deliberate:
-- anyone can sign up choosing "staff", so the assignment is the actual
-- permission, and only an administrator grants it.
--
-- 1. Run this first to see who and what there is:

select p.student_staff_id as staff_number,
       coalesce(nullif(trim(coalesce(p.name, '') || ' ' || coalesce(p.surname, '')), ''), p.email) as staff_name,
       coalesce(string_agg(c.name, ', ' order by c.name), '— not assigned —') as assigned_to
  from public.profiles p
  left join public.staff_cafeterias sc on sc.staff_id = p.id
  left join public.cafeterias c on c.id = sc.cafeteria_id
 where p.role = 'staff'
 group by p.id, p.student_staff_id, p.name, p.surname, p.email
 order by staff_name;

select name as cafeteria from public.cafeterias order by name;

-- 2. Then fill in a staff number and a cafeteria name (or part of it), and run
--    this. Repeat for each assignment; running it twice does nothing extra.
--
-- insert into public.staff_cafeterias (staff_id, cafeteria_id)
-- select p.id, c.id
--   from public.profiles p, public.cafeterias c
--  where p.role = 'staff'
--    and p.student_staff_id = 'YOUR-STAFF-NUMBER'
--    and c.name ilike '%Great Hall%'
-- on conflict do nothing;

-- To remove an assignment:
--
-- delete from public.staff_cafeterias sc
--  using public.profiles p, public.cafeterias c
--  where sc.staff_id = p.id and sc.cafeteria_id = c.id
--    and p.student_staff_id = 'YOUR-STAFF-NUMBER'
--    and c.name ilike '%Great Hall%';
