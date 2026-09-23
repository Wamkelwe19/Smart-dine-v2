-- 0007_storage_policies.sql
--
-- Closes REQ-113. The `menu-images` bucket currently accepts writes from anyone
-- holding the publishable key, which is everyone with the APK.
--
-- Objects are namespaced by cafeteria id: `<cafeteria_id>/<uuid>.<ext>`. That
-- both scopes the write policy and makes REQ-81 (delete the object when the item
-- is deleted or its image replaced) tractable, which a flat root path was not.
-- The current code writes `2026-09-16T10:22:31.123.png` at the bucket root,
-- with colons in the key.

insert into storage.buckets (id, name, public)
values ('menu-images', 'menu-images', true)
on conflict (id) do update set public = true;

-- Extracts the leading folder as a cafeteria id, returning NULL rather than
-- throwing when an object does not follow the convention. Legacy objects sit at
-- the bucket root under names like `2026-09-16T10:22:31.123.png`, so a bare
-- `::uuid` cast in a policy would raise on them instead of simply denying.
create or replace function public.menu_image_cafeteria(object_name text)
returns uuid
language sql
immutable
as $$
  select case
    when (storage.foldername(object_name))[1] ~*
         '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then ((storage.foldername(object_name))[1])::uuid
    else null
  end;
$$;

-- Anyone may read: menu photographs are shown to signed-out users on the splash
-- path and must load without a session.
drop policy if exists "menu_images_public_read" on storage.objects;
create policy "menu_images_public_read" on storage.objects
  for select to public
  using (bucket_id = 'menu-images');

-- Only staff bound to the owning cafeteria may write, and only inside that
-- cafeteria's folder.
drop policy if exists "menu_images_staff_insert" on storage.objects;
create policy "menu_images_staff_insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'menu-images'
    and public.is_staff_of(public.menu_image_cafeteria(name))
  );

drop policy if exists "menu_images_staff_update" on storage.objects;
create policy "menu_images_staff_update" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'menu-images'
    and public.is_staff_of(public.menu_image_cafeteria(name))
  );

drop policy if exists "menu_images_staff_delete" on storage.objects;
create policy "menu_images_staff_delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'menu-images'
    and public.is_staff_of(public.menu_image_cafeteria(name))
  );
