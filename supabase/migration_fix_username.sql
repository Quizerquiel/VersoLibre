-- ============================================================
-- MIGRACIÓN: Corregir username en registro
-- Fecha: 2026-04-08
-- Pegar completo en Supabase → SQL Editor → Run
-- ============================================================

-- 1. Recrear la función que genera usernames seguros (sin cambios, solo por consistencia)
create or replace function public.safe_username(seed text)
returns text
language sql
immutable
as $$
  select coalesce(nullif(regexp_replace(lower(seed), '[^a-z0-9._-]', '', 'g'), ''), 'user');
$$;

-- 2. Actualizar el trigger de creación de usuario
--    CAMBIO PRINCIPAL: ya no se agregan los 4 chars del UUID al username.
--    El username que el usuario eligió se usa tal cual.
--    Solo si ya existe ese username (colisión por registro simultáneo)
--    se agrega el sufijo UUID como último recurso.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  base_name      text;
  base_username  text;
  final_username text;
begin
  base_name     := coalesce(new.raw_user_meta_data ->> 'name', split_part(new.email, '@', 1), 'Autor');
  base_username := left(public.safe_username(coalesce(new.raw_user_meta_data ->> 'username', base_name)), 24);

  -- Usar el username exacto que eligió el usuario.
  -- Solo agregar sufijo UUID si ya existe (condición de carrera entre registros simultáneos).
  if exists (select 1 from public.profiles where username = base_username) then
    final_username := left(base_username || right(new.id::text, 4), 24);
  else
    final_username := base_username;
  end if;

  insert into public.profiles (
    id, email, name, username, bio, role,
    profile_visibility, email_visibility, comment_permissions, sensitive_filter, profile_image
  ) values (
    new.id,
    new.email,
    base_name,
    final_username,
    coalesce(new.raw_user_meta_data ->> 'bio', 'Nueva voz en VersoLibre.'),
    case when lower(new.email) = 'padillajosueezequiel@gmail.com' then 'admin' else 'user' end,
    'public', 'private', 'registered', true, ''
  )
  on conflict (id) do update
    set email = excluded.email,
        role  = case
                  when lower(excluded.email) = 'padillajosueezequiel@gmail.com' then 'admin'
                  else public.profiles.role
                end;

  return new;
end;
$$;

-- 3. Recrear el trigger (por si acaso no existía o estaba desvinculado)
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================
-- NOTA: No se modifica ninguna tabla existente ni se borran datos.
-- Esta migración solo actualiza la lógica de la función trigger.
-- Los usuarios ya registrados con el sufijo UUID NO se modifican
-- automáticamente — sus usernames se pueden cambiar manualmente
-- desde Configuración > Perfil dentro de la app.
-- ============================================================
