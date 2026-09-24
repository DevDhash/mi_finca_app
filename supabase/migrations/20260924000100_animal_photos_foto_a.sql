-- FOTO A only. Apply in Supabase SQL Editor before running this app version.
begin;

alter table public.animals
  add column if not exists remote_photo_path text null;

comment on column public.animals.remote_photo_path is
  'Private animal-photos object key: <user_id>/<animal_id>/<uuid>.<extension>. Never a device path or signed URL.';

-- Preserve animals.photo_path and its data; never backfill from local paths.
insert into storage.buckets (id, name, public)
values ('animal-photos', 'animal-photos', false)
on conflict (id) do update set public = false;

drop policy if exists animal_photos_select_own on storage.objects;
create policy animal_photos_select_own on storage.objects
for select to authenticated
using (
  bucket_id = 'animal-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists animal_photos_insert_own on storage.objects;
create policy animal_photos_insert_own on storage.objects
for insert to authenticated
with check (
  bucket_id = 'animal-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

-- Restrictive guards prevent other permissive Storage policies from broadening
-- access to this bucket. Other buckets are unaffected. No UPDATE/DELETE grants.
drop policy if exists animal_photos_read_guard on storage.objects;
create policy animal_photos_read_guard on storage.objects
as restrictive for select to public
using (
  bucket_id <> 'animal-photos'
  or (auth.role() = 'authenticated'
      and (storage.foldername(name))[1] = (select auth.uid())::text)
);

drop policy if exists animal_photos_insert_guard on storage.objects;
create policy animal_photos_insert_guard on storage.objects
as restrictive for insert to public
with check (
  bucket_id <> 'animal-photos'
  or (auth.role() = 'authenticated'
      and (storage.foldername(name))[1] = (select auth.uid())::text)
);

drop policy if exists animal_photos_no_update on storage.objects;
create policy animal_photos_no_update on storage.objects
as restrictive for update to public
using (bucket_id <> 'animal-photos')
with check (bucket_id <> 'animal-photos');

drop policy if exists animal_photos_no_delete on storage.objects;
create policy animal_photos_no_delete on storage.objects
as restrictive for delete to public
using (bucket_id <> 'animal-photos');

commit;
