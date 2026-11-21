-- =============================================================================
-- 047 — Séparation Driver (Zémidjan/Cloboto/Kloboto) vs Provider (Dépanneur)
-- Dart : app_router.dart, driver_service.dart, driver_home_screen.dart
-- Dépend de : 010, 013, 030
-- =============================================================================
begin;

set local search_path to public, extensions;

-- ── 1. Étendre profiles.role pour accepter 'driver' ────────────────────────
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check
  check (role in ('client', 'driver', 'provider', 'admin'));

-- ── 2. Migrer les providers transport → role='driver' ─────────────────────
update public.profiles
   set role = 'driver',
       updated_at = now()
 where role = 'provider'
   and id in (
     select id from public.providers
     where provider_kind in ('zemidjan', 'tricycle_passenger', 'tricycle_fret')
   );

-- ── 3. RPC register_driver (inscription driver 2 étapes) ──────────────────
create or replace function public.register_driver(
  p_kind              text,
  p_first_name        text default null,
  p_last_name         text default null,
  p_business_name     text default null,
  p_ville             text default null,
  p_photo_profil_url  text default null,
  p_photo_cni_url     text default null,
  p_latitude          double precision default null,
  p_longitude         double precision default null
) returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_phone text;
  v_email text;
  v_prev public.profiles%rowtype;
  v_has_prev boolean;
  v_new_driver boolean := false;
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;
  if p_kind is null or p_kind not in
     ('zemidjan', 'tricycle_passenger', 'tricycle_fret') then
    raise exception 'KIND_INVALIDE' using errcode = '22023';
  end if;
  if p_latitude is null or p_longitude is null
     or p_latitude not between -90 and 90
     or p_longitude not between -180 and 180 then
    raise exception 'POSITION_OBLIGATOIRE' using errcode = '22023';
  end if;
  if nullif(btrim(p_photo_cni_url), '') is null then
    raise exception 'CNI_OBLIGATOIRE' using errcode = '22023';
  end if;

  select * into v_prev from public.profiles where id = v_uid;
  v_has_prev := found;
  if v_has_prev and (v_prev.role = 'admin'
       or (v_prev.inscription_complete and v_prev.role <> 'driver')) then
    raise exception 'ROLE_IMMUABLE' using errcode = 'P0001';
  end if;

  select case when u.phone is null or u.phone = '' then null
              when left(u.phone, 1) = '+' then u.phone
              else '+' || u.phone end,
         nullif(u.email, '')
    into v_phone, v_email
    from auth.users u where u.id = v_uid;

  insert into public.profiles
    (id, role, first_name, last_name, phone, email, photo_profil_url,
     inscription_complete)
  values
    (v_uid, 'driver',
     left(nullif(btrim(p_first_name), ''), 80),
     left(nullif(btrim(p_last_name), ''), 80),
     v_phone,
     coalesce(v_email, null),
     nullif(btrim(p_photo_profil_url), ''),
     true)
  on conflict (id) do update set
    role = 'driver',
    first_name = coalesce(excluded.first_name, public.profiles.first_name),
    last_name  = coalesce(excluded.last_name,  public.profiles.last_name),
    phone      = coalesce(excluded.phone,      public.profiles.phone),
    email      = coalesce(excluded.email,      public.profiles.email),
    photo_profil_url = coalesce(excluded.photo_profil_url,
                                public.profiles.photo_profil_url),
    inscription_complete = true,
    updated_at = now();

  v_new_driver := not exists (select 1 from public.providers where id = v_uid);

  insert into public.providers
    (id, business_name, metier, provider_kind, ville, photo_cni_url,
     latitude, longitude)
  values
    (v_uid,
     coalesce(nullif(btrim(p_business_name), ''),
              nullif(btrim(coalesce(p_first_name,'')||' '||coalesce(p_last_name,'')),''),
              'Conducteur'),
     p_kind, p_kind,
     left(nullif(btrim(p_ville), ''), 300),
     btrim(p_photo_cni_url),
     p_latitude, p_longitude)
  on conflict (id) do update set
    business_name = excluded.business_name,
    metier        = excluded.metier,
    provider_kind = excluded.provider_kind,
    ville         = coalesce(excluded.ville, public.providers.ville),
    photo_cni_url = excluded.photo_cni_url,
    latitude      = excluded.latitude,
    longitude     = excluded.longitude,
    updated_at    = now();

  if v_new_driver then
    perform public.safe_notify_admins(
      'driver_registration',
      'Nouveau conducteur inscrit',
      coalesce(p_business_name, 'Conducteur') || ' (' || p_kind || ')',
      jsonb_build_object('driver_id', v_uid, 'kind', p_kind));
  end if;
end;
$$;

revoke all on function public.register_driver(
  text,text,text,text,text,text,text,double precision,double precision)
  from public, anon;
grant execute on function public.register_driver(
  text,text,text,text,text,text,text,double precision,double precision)
  to authenticated;

-- ── 4. Driver home : courses proches (déjà fait par rides_nearby) ─────────
-- Rien à faire, rides_nearby filtre par provider_kind = service_kind

-- ── 5. Commission rules : ajouter ride_tricycle_passenger ─────────────────
-- (déjà dans 019_commission_rules.sql)

commit;