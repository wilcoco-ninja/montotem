-- =============================================================================
-- 010 — Profils et rôles administrateur
-- Dart : app_user.dart, auth_service.dart, quick_auth_service.dart,
--        admin_roles_screen.dart
-- Dépend de : 002, 003
-- =============================================================================
begin;

set local search_path to public, extensions;

-- Dart : app_user.dart (id, role, first_name, last_name, phone, email,
--        photo_profil_url, inscription_complete, star_points, is_suspended)
create table if not exists public.profiles (
  id                   uuid primary key references auth.users(id) on delete cascade,
  role                 text not null default 'client'
                       check (role in ('client','provider','admin')),
  first_name           text,
  last_name            text,
  phone                text,
  email                text,
  photo_profil_url     text,
  inscription_complete boolean not null default false,
  star_points          integer not null default 0 check (star_points >= 0),
  country_code         text not null default 'BJ',
  is_suspended         boolean not null default false,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

-- Dart : admin_roles_screen.dart (level, granted_by)
create table if not exists public.admin_roles (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  level      text not null default 'support'
             check (level in ('super_admin','finance','support','moderator')),
  granted_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

-- Dart : AppRouter._estAdmin() appelle rpc('is_admin')
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public, extensions
as $$
  select exists(select 1 from public.profiles
                where id = auth.uid() and role = 'admin')
      or exists(select 1 from public.admin_roles
                where user_id = auth.uid());
$$;

create or replace function public.is_super_admin() returns boolean
language sql stable security definer set search_path = public, extensions
as $$
  select exists(select 1 from public.admin_roles
                where user_id = auth.uid() and level = 'super_admin');
$$;

grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_super_admin() to authenticated;

drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Bootstrap admin initial (adaptez l'UUID à votre compte wadam982@gmail.com)
insert into public.profiles (id, role, inscription_complete)
select id, 'admin', true from auth.users where email = 'wadam982@gmail.com'
on conflict (id) do update set role = 'admin', inscription_complete = true;

insert into public.admin_roles (user_id, level)
select id, 'super_admin' from auth.users where email = 'wadam982@gmail.com'
on conflict (user_id) do update set level = 'super_admin';

commit;