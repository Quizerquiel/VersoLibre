create extension if not exists "pgcrypto";

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  name text not null,
  username text not null unique,
  bio text default 'Sin biografia por ahora.',
  role text not null default 'user' check (role in ('user','admin')),
  profile_visibility text not null default 'public' check (profile_visibility in ('public','registered','private')),
  email_visibility text not null default 'private' check (email_visibility in ('public','registered','private')),
  comment_permissions text not null default 'registered' check (comment_permissions in ('registered','followers','nobody')),
  sensitive_filter boolean not null default true,
  profile_image text default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.poems (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  author_name text not null,
  title text not null,
  category_id text not null,
  category_label text not null,
  content text not null,
  status text not null default 'published' check (status in ('published','hidden')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.reactions (
  poem_id uuid not null references public.poems(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  value smallint not null check (value in (-1,1)),
  created_at timestamptz not null default now(),
  primary key (poem_id, user_id)
);

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  poem_id uuid not null references public.poems(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  author_name text not null,
  content text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists trg_poems_updated_at on public.poems;
create trigger trg_poems_updated_at before update on public.poems
for each row execute function public.set_updated_at();

drop trigger if exists trg_comments_updated_at on public.comments;
create trigger trg_comments_updated_at before update on public.comments
for each row execute function public.set_updated_at();

create or replace function public.safe_username(seed text)
returns text
language sql
immutable
as $$
  select coalesce(nullif(regexp_replace(lower(seed), '[^a-z0-9._-]', '', 'g'), ''), 'user');
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  base_name text;
  base_username text;
begin
  base_name := coalesce(new.raw_user_meta_data ->> 'name', split_part(new.email, '@', 1), 'Autor');
  base_username := public.safe_username(coalesce(new.raw_user_meta_data ->> 'username', base_name));

  insert into public.profiles (
    id,
    email,
    name,
    username,
    bio,
    role,
    profile_visibility,
    email_visibility,
    comment_permissions,
    sensitive_filter,
    profile_image
  ) values (
    new.id,
    new.email,
    base_name,
    left(base_username || right(new.id::text, 4), 24),
    coalesce(new.raw_user_meta_data ->> 'bio', 'Nueva voz en VersoLibre.'),
    case when lower(new.email) = 'padillajosueezequiel@gmail.com' then 'admin' else 'user' end,
    'public',
    'private',
    'registered',
    true,
    ''
  )
  on conflict (id) do update
    set email = excluded.email,
        role = case when lower(excluded.email) = 'padillajosueezequiel@gmail.com' then 'admin' else public.profiles.role end;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.is_admin(uid uuid)
returns boolean
language sql
stable
as $$
  select exists(select 1 from public.profiles p where p.id = uid and p.role = 'admin');
$$;

alter table public.profiles enable row level security;
alter table public.poems enable row level security;
alter table public.reactions enable row level security;
alter table public.comments enable row level security;

drop policy if exists "profiles_select" on public.profiles;
create policy "profiles_select" on public.profiles for select using (true);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles for insert with check (auth.uid() = id);

drop policy if exists "profiles_update_own_or_admin" on public.profiles;
create policy "profiles_update_own_or_admin" on public.profiles
for update using (auth.uid() = id or public.is_admin(auth.uid()))
with check (auth.uid() = id or public.is_admin(auth.uid()));

drop policy if exists "poems_select_public_owner_admin" on public.poems;
create policy "poems_select_public_owner_admin" on public.poems
for select using (status = 'published' or owner_id = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists "poems_insert_own" on public.poems;
create policy "poems_insert_own" on public.poems
for insert with check (owner_id = auth.uid());

drop policy if exists "poems_update_owner_or_admin" on public.poems;
create policy "poems_update_owner_or_admin" on public.poems
for update using (owner_id = auth.uid() or public.is_admin(auth.uid()))
with check (owner_id = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists "poems_delete_owner_or_admin" on public.poems;
create policy "poems_delete_owner_or_admin" on public.poems
for delete using (owner_id = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists "reactions_select_all" on public.reactions;
create policy "reactions_select_all" on public.reactions for select using (true);

drop policy if exists "reactions_insert_own" on public.reactions;
create policy "reactions_insert_own" on public.reactions
for insert with check (user_id = auth.uid());

drop policy if exists "reactions_update_own" on public.reactions;
create policy "reactions_update_own" on public.reactions
for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "reactions_delete_own" on public.reactions;
create policy "reactions_delete_own" on public.reactions
for delete using (user_id = auth.uid());

drop policy if exists "comments_select_all" on public.comments;
create policy "comments_select_all" on public.comments for select using (true);

drop policy if exists "comments_insert_own" on public.comments;
create policy "comments_insert_own" on public.comments
for insert with check (user_id = auth.uid());

drop policy if exists "comments_update_own_or_admin" on public.comments;
create policy "comments_update_own_or_admin" on public.comments
for update using (user_id = auth.uid() or public.is_admin(auth.uid()))
with check (user_id = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists "comments_delete_own_or_admin" on public.comments;
create policy "comments_delete_own_or_admin" on public.comments
for delete using (user_id = auth.uid() or public.is_admin(auth.uid()));

create index if not exists idx_poems_created_at on public.poems(created_at desc);
create index if not exists idx_poems_owner on public.poems(owner_id);
create index if not exists idx_reactions_poem on public.reactions(poem_id);
create index if not exists idx_comments_poem_created on public.comments(poem_id, created_at desc);
