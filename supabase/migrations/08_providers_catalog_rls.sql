-- =============================================================================
-- MONTOTEM : Script 08 - Prestataires, catalogue, carte, inscription, RLS
-- Fichier  : sql/08_providers_catalog_rls.sql
-- Prérequis : scripts 01b, 04b, 05, 07 exécutés. Idempotent.
-- =============================================================================
begin;

set local search_path to public, extensions;

-- -----------------------------------------------------------------------------
-- 1. providers : colonnes complémentaires
-- -----------------------------------------------------------------------------
alter table public.providers
  add column if not exists vehicle_types         text[]      not null default '{}',
  add column if not exists rayon_max_km          integer     not null default 15,
  add column if not exists whatsapp              text,
  add column if not exists momo_operateur        text,
  add column if not exists momo_numero           text,
  add column if not exists momo_titulaire        text,
  add column if not exists id_document_type      text,
  add column if not exists id_document_number    text,
  add column if not exists photo_cni_back_url    text,
  add column if not exists photo_selfie_url      text,
  add column if not exists photo_garage_url      text,
  add column if not exists garage_description    text,
  add column if not exists id_checks             jsonb       not null default '{}'::jsonb,
  add column if not exists identity_submitted_at timestamptz;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'providers_vehicle_types_check') then
    alter table public.providers add constraint providers_vehicle_types_check
      check (vehicle_types <@ array['moto', 'voiture', 'camion']::text[]);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'providers_rayon_check') then
    alter table public.providers add constraint providers_rayon_check
      check (rayon_max_km between 1 and 50);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'providers_tarif_km_check') then
    alter table public.providers add constraint providers_tarif_km_check
      check (tarif_km_fcfa between 0 and 5000);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'providers_frais_min_check') then
    alter table public.providers add constraint providers_frais_min_check
      check (frais_deplacement_min_fcfa between 0 and 100000);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'providers_momo_operateur_check') then
    alter table public.providers add constraint providers_momo_operateur_check
      check (momo_operateur is null or momo_operateur in ('mtn', 'moov', 'celtiis'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'providers_id_document_type_check') then
    alter table public.providers add constraint providers_id_document_type_check
      check (id_document_type is null
             or id_document_type in ('cni', 'passeport', 'permis', 'carte_electeur'));
  end if;
end $$;

create index if not exists idx_providers_lat_lng
  on public.providers (latitude, longitude) where statut_validation = 'approved';

-- Déduit provider_kind (script 07) du métier saisi à l'inscription.
create or replace function public.provider_kind_from_metier(p_metier text)
returns text
language sql
immutable
as $$
  select case
    when lower(coalesce(p_metier, '')) like '%zemidjan%'
      or lower(coalesce(p_metier, '')) like '%zémidjan%'      then 'zemidjan'
    when lower(coalesce(p_metier, '')) like '%tricycle%'      then 'tricycle_fret'
    when lower(coalesce(p_metier, '')) like '%vulcanis%'
      or lower(coalesce(p_metier, '')) like '%pneu%'          then 'vulcanisateur'
    when lower(coalesce(p_metier, '')) like '%électric%'
      or lower(coalesce(p_metier, '')) like '%electric%'      then 'electricien'
    when lower(coalesce(p_metier, '')) like '%essence%'
      or lower(coalesce(p_metier, '')) like '%station%'       then 'station'
    when lower(coalesce(p_metier, '')) like '%garage%'        then 'garage'
    else 'mecanicien'
  end;
$$;

create or replace function public.providers_default_kind()
returns trigger
language plpgsql
as $$
begin
  if new.provider_kind is null then
    new.provider_kind := public.provider_kind_from_metier(new.metier);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_providers_default_kind on public.providers;
create trigger trg_providers_default_kind
  before insert or update of metier on public.providers
  for each row execute function public.providers_default_kind();

update public.providers
   set provider_kind = public.provider_kind_from_metier(metier)
 where provider_kind is null;

-- Un prestataire ne peut passer en ligne que validé et non bloqué.
create or replace function public.providers_guard_available()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.disponible and not coalesce(old.disponible, false) then
    if new.statut_validation <> 'approved' then
      raise exception 'PRESTATAIRE_NON_VALIDE' using errcode = 'P0001';
    end if;
    if exists (
      select 1 from public.wallets w
       where w.provider_id = new.id and w.blocked
    ) then
      raise exception 'WALLET_BLOQUE' using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_providers_guard_available on public.providers;
create trigger trg_providers_guard_available
  before update of disponible on public.providers
  for each row execute function public.providers_guard_available();

drop trigger if exists trg_providers_updated_at on public.providers;
create trigger trg_providers_updated_at
  before update on public.providers
  for each row execute function public.set_updated_at();

drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- 2. Compétences et catalogue de prestations
-- -----------------------------------------------------------------------------
create table if not exists public.provider_skills (
  id          uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.providers (id) on delete cascade,
  label       text not null check (char_length(label) between 2 and 60),
  created_at  timestamptz not null default now()
);

create unique index if not exists uq_provider_skills_label
  on public.provider_skills (provider_id, lower(label));

create table if not exists public.provider_catalog_items (
  id                 uuid primary key default gen_random_uuid(),
  provider_id        uuid not null references public.providers (id) on delete cascade,
  nom                text not null check (char_length(btrim(nom)) between 2 and 80),
  categorie_vehicule text not null check (categorie_vehicule in ('moto', 'voiture', 'camion')),
  mode_prix          text not null check (mode_prix in ('fixe', 'devis')),
  prix_fcfa          integer check (prix_fcfa is null or prix_fcfa > 0),
  created_at         timestamptz not null default now(),
  constraint catalog_items_price_consistency
    check ((mode_prix = 'fixe' and prix_fcfa is not null) or mode_prix = 'devis')
);

create index if not exists idx_catalog_items_provider
  on public.provider_catalog_items (provider_id, created_at);

-- -----------------------------------------------------------------------------
-- 3. Row Level Security
-- -----------------------------------------------------------------------------
alter table public.profiles               enable row level security;
alter table public.providers              enable row level security;
alter table public.provider_skills        enable row level security;
alter table public.provider_catalog_items enable row level security;
alter table public.missions               enable row level security;
alter table public.mission_events         enable row level security;
alter table public.provider_reports       enable row level security;

-- profiles
drop policy if exists profiles_select_own on public.profiles;
drop policy if exists profiles_select     on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or public.is_admin());

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- providers
drop policy if exists providers_select_own on public.providers;
drop policy if exists providers_select     on public.providers;
create policy providers_select on public.providers
  for select to authenticated
  using (id = (select auth.uid()) or public.is_admin());

drop policy if exists providers_update_own on public.providers;
create policy providers_update_own on public.providers
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- compétences / catalogue : lecture propriétaire ou admin, écriture via RPC
drop policy if exists provider_skills_select on public.provider_skills;
create policy provider_skills_select on public.provider_skills
  for select to authenticated
  using (provider_id = (select auth.uid()) or public.is_admin());

drop policy if exists catalog_items_select on public.provider_catalog_items;
create policy catalog_items_select on public.provider_catalog_items
  for select to authenticated
  using (provider_id = (select auth.uid()) or public.is_admin());

-- missions : participants ou admin
drop policy if exists missions_select on public.missions;
create policy missions_select on public.missions
  for select to authenticated
  using (
    client_id = (select auth.uid())
    or provider_id = (select auth.uid())
    or public.is_admin()
  );

-- journal et signalements : admin uniquement (écriture via RPC)
drop policy if exists mission_events_select on public.mission_events;
create policy mission_events_select on public.mission_events
  for select to authenticated using (public.is_admin());

drop policy if exists provider_reports_select on public.provider_reports;
create policy provider_reports_select on public.provider_reports
  for select to authenticated using (public.is_admin());

-- Privilèges de table : l'anonyme n'a aucun accès direct ; les utilisateurs
-- connectés ne peuvent écrire que les colonnes explicitement autorisées.
revoke all on public.profiles, public.providers, public.provider_skills,
              public.provider_catalog_items, public.missions,
              public.mission_events, public.provider_reports
  from anon;

revoke insert, update, delete on public.profiles, public.providers,
              public.provider_skills, public.provider_catalog_items,
              public.missions, public.mission_events, public.provider_reports
  from authenticated;

grant update (first_name, last_name, photo_profil_url) on public.profiles  to authenticated;
grant update (disponible)                              on public.providers to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Suppression des failles héritées des scripts 05 / 06
-- -----------------------------------------------------------------------------
drop function if exists public.pay_mission_travel_fee(uuid);
revoke all on function public.log_mission_event(uuid, text, jsonb)
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 5. Inscription : register_profile
-- -----------------------------------------------------------------------------
create or replace function public.register_profile(
  p_role             text,
  p_first_name       text             default null,
  p_last_name        text             default null,
  p_email            text             default null,
  p_phone            text             default null,
  p_photo_profil_url text             default null,
  p_business_name    text             default null,
  p_metier           text             default null,
  p_ville            text             default null,
  p_ifu              text             default null,
  p_photo_cni_url    text             default null,
  p_latitude         double precision default null,
  p_longitude        double precision default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid         uuid := auth.uid();
  v_phone       text;
  v_email       text;
  v_prev        public.profiles%rowtype;
  v_has_prev    boolean;
  v_bn          text := nullif(btrim(p_business_name), '');
  v_metier      text := nullif(btrim(p_metier), '');
  v_new_provider boolean := false;
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;
  if p_role is null or p_role not in ('client', 'provider') then
    raise exception 'ROLE_INVALIDE' using errcode = '22023';
  end if;

  select * into v_prev from public.profiles where id = v_uid;
  v_has_prev := found;
  if v_has_prev and (
       v_prev.role = 'admin'
       or (v_prev.inscription_complete and v_prev.role <> p_role)
     ) then
    raise exception 'ROLE_IMMUABLE' using errcode = 'P0001';
  end if;

  if p_role = 'provider' then
    if v_bn is null or v_metier is null then
      raise exception 'CHAMPS_OBLIGATOIRES' using errcode = '22023';
    end if;
    if p_latitude is null or p_longitude is null
       or p_latitude not between -90 and 90
       or p_longitude not between -180 and 180 then
      raise exception 'POSITION_OBLIGATOIRE' using errcode = '22023';
    end if;
    if nullif(btrim(p_photo_cni_url), '') is null then
      raise exception 'CNI_OBLIGATOIRE' using errcode = '22023';
    end if;
  end if;

  -- Téléphone et e-mail lus côté serveur : jamais fournis par le client.
  select
    case
      when u.phone is null or u.phone = '' then null
      when left(u.phone, 1) = '+'          then u.phone
      else '+' || u.phone
    end,
    nullif(u.email, '')
    into v_phone, v_email
    from auth.users u
   where u.id = v_uid;

  insert into public.profiles
    (id, role, first_name, last_name, phone, email, photo_profil_url, inscription_complete)
  values
    (v_uid, p_role,
     left(nullif(btrim(p_first_name), ''), 80),
     left(nullif(btrim(p_last_name), ''), 80),
     v_phone,
     coalesce(v_email, nullif(btrim(p_email), '')),
     nullif(btrim(p_photo_profil_url), ''),
     true)
  on conflict (id) do update set
    role                 = excluded.role,
    first_name           = coalesce(excluded.first_name,       public.profiles.first_name),
    last_name            = coalesce(excluded.last_name,        public.profiles.last_name),
    phone                = coalesce(excluded.phone,            public.profiles.phone),
    email                = coalesce(excluded.email,            public.profiles.email),
    photo_profil_url     = coalesce(excluded.photo_profil_url, public.profiles.photo_profil_url),
    inscription_complete = true,
    updated_at           = now();

  if p_role = 'provider' then
    v_new_provider := not exists (select 1 from public.providers where id = v_uid);

    insert into public.providers
      (id, business_name, metier, ville, ifu, photo_cni_url, latitude, longitude)
    values
      (v_uid, left(v_bn, 120), left(v_metier, 80),
       left(nullif(btrim(p_ville), ''), 300),
       left(nullif(btrim(p_ifu), ''), 40),
       btrim(p_photo_cni_url), p_latitude, p_longitude)
    on conflict (id) do update set
      business_name = excluded.business_name,
      metier        = excluded.metier,
      ville         = coalesce(excluded.ville, public.providers.ville),
      ifu           = coalesce(excluded.ifu,   public.providers.ifu),
      photo_cni_url = excluded.photo_cni_url,
      latitude      = excluded.latitude,
      longitude     = excluded.longitude,
      statut_validation = case when public.providers.statut_validation = 'rejected'
                               then 'pending' else public.providers.statut_validation end,
      rejection_reason  = case when public.providers.statut_validation = 'rejected'
                               then null else public.providers.rejection_reason end,
      updated_at    = now();

    if v_new_provider then
      begin
        perform public.notify_admins(
          'provider_registration',
          'Nouveau dossier prestataire',
          v_bn || ' (' || v_metier || ')',
          jsonb_build_object('provider_id', v_uid)
        );
      exception when others then
        null;
      end;
    end if;
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- 6. Carte : prestataires visibles (validés + abonnement actif + non suspendus)
-- -----------------------------------------------------------------------------
create or replace function public.providers_in_bounds(
  p_min_lat double precision,
  p_min_lng double precision,
  p_max_lat double precision,
  p_max_lng double precision,
  p_limit   integer default 400
) returns table (
  id                   uuid,
  nom                  text,
  metier               text,
  latitude             double precision,
  longitude            double precision,
  telephone            text,
  photo_url            text,
  business_name        text,
  adresse              text,
  verifie              boolean,
  disponible           boolean,
  note_moyenne         numeric,
  clients_satisfaits   integer,
  clients_insatisfaits integer,
  missions_completees  integer,
  statut_mission       text,
  vehicle_types        text[]
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select pv.id,
         coalesce(nullif(btrim(coalesce(pf.first_name, '') || ' ' || coalesce(pf.last_name, '')), ''),
                  'Prestataire'),
         pv.metier,
         pv.latitude,
         pv.longitude,
         case when auth.uid() is not null then pf.phone end,
         pf.photo_profil_url,
         pv.business_name,
         pv.ville,
         true,
         pv.disponible,
         pv.note_moyenne,
         pv.clients_satisfaits,
         pv.clients_insatisfaits,
         pv.missions_completees,
         pv.statut_mission,
         pv.vehicle_types
    from public.providers pv
    join public.profiles  pf on pf.id = pv.id
   where pv.statut_validation = 'approved'
     and pv.fin_abonnement > now()
     and not pf.is_suspended
     and pv.latitude between p_min_lat and p_max_lat
     and case when p_min_lng <= p_max_lng
              then pv.longitude between p_min_lng and p_max_lng
              else (pv.longitude >= p_min_lng or pv.longitude <= p_max_lng)
         end
   order by (pv.palier = 'premium') desc nulls last, pv.note_moyenne desc
   limit least(greatest(coalesce(p_limit, 400), 1), 2000);
$$;

create or replace function public.providers_nearby()
returns table (
  id                   uuid,
  nom                  text,
  metier               text,
  latitude             double precision,
  longitude            double precision,
  telephone            text,
  photo_url            text,
  business_name        text,
  adresse              text,
  verifie              boolean,
  disponible           boolean,
  note_moyenne         numeric,
  clients_satisfaits   integer,
  clients_insatisfaits integer,
  missions_completees  integer,
  statut_mission       text,
  vehicle_types        text[]
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select * from public.providers_in_bounds(-90, -180, 90, 180, 2000);
$$;

create or replace function public.provider_vehicle_map()
returns table (provider_id uuid, vehicle_types text[])
language sql
stable
security definer
set search_path = public, extensions
as $$
  select pv.id, pv.vehicle_types
    from public.providers pv
    join public.profiles  pf on pf.id = pv.id
   where pv.statut_validation = 'approved'
     and pv.fin_abonnement > now()
     and not pf.is_suspended;
$$;

-- -----------------------------------------------------------------------------
-- 7. Fiche publique d'un prestataire (grille tarifaire, compétences)
-- -----------------------------------------------------------------------------
create or replace function public.provider_public_catalog(p_provider uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_pv public.providers%rowtype;
begin
  select pv.* into v_pv
    from public.providers pv
    join public.profiles  pf on pf.id = pv.id
   where pv.id = p_provider
     and pv.statut_validation = 'approved'
     and pv.fin_abonnement > now()
     and not pf.is_suspended;
  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'vehicle_types', to_jsonb(v_pv.vehicle_types),
    'skills', coalesce((
        select jsonb_agg(s.label order by s.created_at)
          from public.provider_skills s where s.provider_id = p_provider
      ), '[]'::jsonb),
    'tarif_km_fcfa', v_pv.tarif_km_fcfa,
    'frais_deplacement_min_fcfa', v_pv.frais_deplacement_min_fcfa,
    'rayon_max_km', v_pv.rayon_max_km,
    'services', coalesce((
        select jsonb_agg(
                 jsonb_build_object(
                   'nom', i.nom,
                   'categorie_vehicule', i.categorie_vehicule,
                   'mode_prix', i.mode_prix,
                   'prix_fcfa', i.prix_fcfa)
                 order by i.created_at, i.id)
          from public.provider_catalog_items i where i.provider_id = p_provider
      ), '[]'::jsonb),
    'id_document_type', v_pv.id_document_type,
    'photo_garage_url', v_pv.photo_garage_url,
    'garage_description', v_pv.garage_description
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 8. Catalogue du prestataire connecté (remplacement en bloc)
-- -----------------------------------------------------------------------------
create or replace function public.set_provider_catalog(
  p_vehicle_types text[],
  p_services      jsonb,
  p_tarif_km      integer,
  p_frais_min     integer,
  p_rayon_km      integer,
  p_whatsapp      text default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid  uuid := auth.uid();
  v_item jsonb;
  v_nom  text;
  v_cat  text;
  v_mode text;
  v_prix integer;
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;
  if not exists (select 1 from public.providers where id = v_uid) then
    raise exception 'PAS_PRESTATAIRE' using errcode = 'P0002';
  end if;

  if p_vehicle_types is null
     or cardinality(p_vehicle_types) = 0
     or not (p_vehicle_types <@ array['moto', 'voiture', 'camion']::text[]) then
    raise exception 'VEHICULES_OBLIGATOIRES' using errcode = '22023';
  end if;

  if p_services is null
     or jsonb_typeof(p_services) <> 'array'
     or jsonb_array_length(p_services) = 0 then
    raise exception 'SERVICES_OBLIGATOIRES' using errcode = '22023';
  end if;

  if p_tarif_km  is null or p_tarif_km  not between 0 and 5000
     or p_frais_min is null or p_frais_min not between 0 and 100000
     or p_rayon_km  is null or p_rayon_km  not between 1 and 50 then
    raise exception 'TARIF_INVALIDE' using errcode = '22023';
  end if;

  delete from public.provider_catalog_items where provider_id = v_uid;

  for v_item in select * from jsonb_array_elements(p_services) loop
    v_nom  := left(btrim(coalesce(v_item ->> 'nom', '')), 80);
    v_cat  := v_item ->> 'categorie_vehicule';
    v_mode := coalesce(v_item ->> 'mode_prix', 'devis');

    if char_length(v_nom) < 2
       or v_cat is null or not (v_cat = any (p_vehicle_types))
       or v_mode not in ('fixe', 'devis') then
      raise exception 'SERVICE_INVALIDE' using errcode = '22023';
    end if;

    v_prix := null;
    if v_mode = 'fixe' then
      begin
        v_prix := (v_item ->> 'prix_fcfa')::integer;
      exception when others then
        v_prix := null;
      end;
      if v_prix is null or v_prix <= 0 or v_prix > 10000000 then
        raise exception 'TARIF_INVALIDE' using errcode = '22023';
      end if;
    end if;

    insert into public.provider_catalog_items
      (provider_id, nom, categorie_vehicule, mode_prix, prix_fcfa)
    values (v_uid, v_nom, v_cat, v_mode, v_prix);
  end loop;

  update public.providers
     set vehicle_types = (select array_agg(distinct x order by x) from unnest(p_vehicle_types) as x),
         tarif_km_fcfa = p_tarif_km,
         frais_deplacement_min_fcfa = p_frais_min,
         rayon_max_km  = p_rayon_km,
         whatsapp      = left(nullif(btrim(regexp_replace(coalesce(p_whatsapp, ''), '[^0-9+ ]', '', 'g')), ''), 20)
   where id = v_uid;
end;
$$;

-- -----------------------------------------------------------------------------
-- 9. Compétences libres
-- -----------------------------------------------------------------------------
create or replace function public.add_provider_skill(p_label text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid   uuid := auth.uid();
  v_label text := regexp_replace(btrim(coalesce(p_label, '')), '\s+', ' ', 'g');
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;
  if not exists (select 1 from public.providers where id = v_uid) then
    raise exception 'PAS_PRESTATAIRE' using errcode = 'P0002';
  end if;
  if char_length(v_label) not between 2 and 60 then
    raise exception 'COMPETENCE_INVALIDE' using errcode = '22023';
  end if;
  if (select count(*) from public.provider_skills where provider_id = v_uid) >= 30 then
    raise exception 'TROP_DE_COMPETENCES' using errcode = 'P0001';
  end if;

  insert into public.provider_skills (provider_id, label)
  values (v_uid, v_label)
  on conflict do nothing;
end;
$$;

create or replace function public.remove_provider_skill(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;
  delete from public.provider_skills where id = p_id and provider_id = v_uid;
end;
$$;

-- -----------------------------------------------------------------------------
-- 10. Droits d'exécution des RPC
-- -----------------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig, p.proname
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in (
         'register_profile', 'set_provider_catalog', 'add_provider_skill',
         'remove_provider_skill', 'create_mission', 'report_mission_prank',
         'providers_in_bounds', 'providers_nearby', 'provider_vehicle_map',
         'provider_public_catalog'
       )
  loop
    execute format('revoke all on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated', r.sig);
    if r.proname in ('providers_in_bounds', 'providers_nearby',
                     'provider_vehicle_map', 'provider_public_catalog') then
      execute format('grant execute on function %s to anon', r.sig);
    end if;
  end loop;
end $$;

commit;