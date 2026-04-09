-- ============================================================
-- MIGRACIÓN: Bucket de Storage para fotos de perfil
-- Fecha: 2026-04-09
-- Pegar completo en Supabase → SQL Editor → Run
-- ============================================================

-- 1. Crear el bucket "avatars" (público, límite 2 MB por archivo)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars',
  'avatars',
  true,
  2097152,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do nothing;

-- 2. Política: cualquiera puede ver los avatares
drop policy if exists "avatars_public_read" on storage.objects;
create policy "avatars_public_read"
  on storage.objects for select
  using (bucket_id = 'avatars');

-- 3. Política: usuarios autenticados pueden subir su propio avatar
--    La ruta esperada es: {user_id}/avatar.jpg
drop policy if exists "avatars_upload_own" on storage.objects;
create policy "avatars_upload_own"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and name like auth.uid()::text || '/%'
  );

-- 4. Política: usuarios pueden reemplazar su propio avatar (upsert)
drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and name like auth.uid()::text || '/%'
  );

-- 5. Política: usuarios pueden borrar su propio avatar
drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and name like auth.uid()::text || '/%'
  );

-- ============================================================
-- NOTA: No se modifica ninguna tabla existente ni se borran datos.
-- Las fotos antiguas guardadas como base64 en profile_image
-- siguen funcionando — solo las nuevas subidas van a Storage.
-- ============================================================
