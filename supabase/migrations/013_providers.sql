-- =============================================================================
-- 013 — Prestataires : conducteurs + dépannage
-- Dart : provider_catalog_service.dart, ride_driver_service.dart,
--        provider_identity_service.dart, provider_trades.dart
-- Dépend de : 010, 012
-- =============================================================================
begin;

set local search_path to public, extensions;

-- Dart : ProviderPublicCatalog, DriverInfo, IdentityStatus
create table if not exists public.providers (
  id                         uuid primary key references public.profiles(id) on delete cascade,
  business_name              text not null,
  metier                     text not null,

  -- 3 kinds conducteurs + 5 kinds dépannage
  provider_kind              text not null check (provider_kind in (
    'zemidjan',                 -- moto 1 passager
    'tricycle_passenger',       -- kloboto 2-3 personnes
    'tricycle_fret',            -- kloboto colis
    'mecanicien',               -- travailleur seul
    'vulcanisateur',            -- travailleur seul
    'electricien',              -- travailleur seul
    'garage',                   -- équipe + remorquage
    'station'                   -- station-service
  )),
  structure_type             text not null default 'solo'
                             check (structure_type in ('solo','equipe')),
  equipe_taille              integer not null default 1
                             check (equipe_taille between 1 and 50),
  remorquage_actif           boolean not null default false,

  ville                      text,
  ifu                        text,
  latitude                   double precision not null
                             check (latitude between -90 and 90),
  longitude                  double precision not null
                             check (longitude between -180 and 180),
  location                   geography(Point, 4326),
  location_updated_at        timestamptz,
  disponible                 boolean not null default false,
  statut_validation          text not null default 'pending'
                             check (statut_validation in ('pending','approved','rejected')),
  rejection_reason           text,
  validated_at               timestamptz,
  validated_by               uuid references public.profiles(id),
  note_moyenne               numeric(3,2) not null default 0,
  clients_satisfaits         integer not null default 0,
  clients_insatisfaits       integer not null default 0,
  missions_completees        integer not null default 0,
  statut_mission             text,
  tarif_km_fcfa              integer not null default 100
                             check (tarif_km_fcfa between 0 and 5000),
  frais_deplacement_min_fcfa integer not null default 1000
                             check (frais_deplacement_min_fcfa between 0 and 100000),
  rayon_max_km               integer not null default 15
                             check (rayon_max_km between 1 and 50),

  -- 5 catégories de véhicules pris en charge
  vehicle_types              text[] not null default '{}'
                             check (vehicle_types <@
                               array['moto','tricycle','voiture','bus','camion']::text[]),

  whatsapp                   text,
  momo_operateur             text check (momo_operateur is null or momo_operateur in ('mtn','moov','celtiis')),
  momo_numero                text,
  momo_titulaire             text,
  id_document_type           text check (id_document_type is null or id_document_type in ('cni','passeport','permis','carte_electeur')),
  id_document_number         text,
  photo_cni_url              text,
  photo_cni_back_url         text,
  photo_selfie_url           text,
  photo_garage_url           text,
  garage_description         text,
  id_checks                  jsonb not null default '{}'::jsonb,
  identity_submitted_at      timestamptz,
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now()
);

create index if not exists idx_providers_location on public.providers using gist (location);
create index if not exists idx_providers_kind     on public.providers (provider_kind);
create index if not exists idx_providers_lat_lng  on public.providers (latitude, longitude)
  where statut_validation = 'approved';

-- Seul le garage peut remorquer
alter table public.providers
  drop constraint if exists providers_remorquage_check;
alter table public.providers
  add constraint providers_remorquage_check
  check (remorquage_actif = false or provider_kind = 'garage');

-- Cohérence structure/équipe
alter table public.providers
  drop constraint if exists providers_equipe_check;
alter table public.providers
  add constraint providers_equipe_check
  check (
    (structure_type = 'solo'   and equipe_taille = 1)
    or (structure_type = 'equipe' and equipe_taille >= 2)
  );

-- Trigger : sync location
create or replace function public.providers_sync_location()
returns trigger language plpgsql set search_path = public, extensions
as $$
begin
  if new.latitude is not null and new.longitude is not null then
    new.location := st_setsrid(st_makepoint(new.longitude, new.latitude), 4326)::geography;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_providers_sync_location on public.providers;
create trigger trg_providers_sync_location
  before insert or update of latitude, longitude on public.providers
  for each row execute function public.providers_sync_location();

drop trigger if exists trg_providers_updated_at on public.providers;
create trigger trg_providers_updated_at
  before update on public.providers
  for each row execute function public.set_updated_at();

-- Dérivation provider_kind depuis le métier
create or replace function public.provider_kind_from_metier(p_metier text)
returns text language sql immutable as $$
  select case
    when lower(coalesce(p_metier,'')) like '%zemidjan%'
      or lower(coalesce(p_metier,'')) like '%zémidjan%'      then 'zemidjan'
    when lower(coalesce(p_metier,'')) like '%tricycle%'
      and lower(coalesce(p_metier,'')) like '%fret%'         then 'tricycle_fret'
    when lower(coalesce(p_metier,'')) like '%tricycle%'
      and lower(coalesce(p_metier,'')) like '%colis%'        then 'tricycle_fret'
    when lower(coalesce(p_metier,'')) like '%tricycle%'      then 'tricycle_passenger'
    when lower(coalesce(p_metier,'')) like '%vulcanis%'
      or lower(coalesce(p_metier,'')) like '%pneu%'          then 'vulcanisateur'
    when lower(coalesce(p_metier,'')) like '%électric%'
      or lower(coalesce(p_metier,'')) like '%electric%'      then 'electricien'
    when lower(coalesce(p_metier,'')) like '%garage%'
      or lower(coalesce(p_metier,'')) like '%carross%'       then 'garage'
    when lower(coalesce(p_metier,'')) like '%essence%'
      or lower(coalesce(p_metier,'')) like '%station%'       then 'station'
    else 'mecanicien' end;
$$;

create or replace function public.providers_default_kind()
returns trigger language plpgsql as $$
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

commit;