-- =============================================================================
-- MONTOTEM : Script 05 - Schéma Complet et Autonome (Profils, Prestataires, Missions)
-- Fichier  : 05_missions_and_travel_fees.sql
-- =============================================================================

begin;

-- 1. Fonction Haversine pour le calcul de distance
create or replace function public.haversine_km(
  a_lat double precision, a_lng double precision,
  b_lat double precision, b_lng double precision
) returns double precision
language sql immutable set search_path = ''
as $$
  select 6371.0 * 2 * asin(least(1.0, sqrt(
    power(sin(radians(b_lat - a_lat) / 2), 2)
    + cos(radians(a_lat)) * cos(radians(b_lat))
      * power(sin(radians(b_lng - a_lng) / 2), 2))));
$$;

-- 2. Table des profils utilisateurs si elle n'existe pas
create table if not exists public.profiles (
  id                   uuid primary key references auth.users (id) on delete cascade,
  role                 text not null default 'client',
  first_name           text,
  last_name            text,
  phone                text,
  email                text,
  photo_profil_url     text,
  inscription_complete boolean not null default false,
  star_points          integer not null default 0 check (star_points >= 0),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint profiles_role_check check (role in ('client', 'provider', 'admin'))
);

-- 3. Table des prestataires si elle n'existe pas
create table if not exists public.providers (
  id                   uuid primary key references public.profiles (id) on delete cascade,
  business_name        text not null,
  metier               text not null,
  ville                text,
  ifu                  text,
  photo_cni_url        text,
  latitude             double precision not null,
  longitude            double precision not null,
  disponible           boolean not null default false,
  statut_validation    text not null default 'pending',
  rejection_reason     text,
  validated_at         timestamptz,
  validated_by         uuid references public.profiles (id),
  palier               text,
  fin_abonnement       timestamptz,
  note_moyenne         numeric(3, 2) not null default 0,
  clients_satisfaits   integer not null default 0,
  clients_insatisfaits integer not null default 0,
  missions_completees  integer not null default 0,
  statut_mission       text,
  tarif_km_fcfa        integer not null default 100,
  frais_deplacement_min_fcfa integer not null default 1000,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint providers_latitude_check   check (latitude between -90 and 90),
  constraint providers_longitude_check  check (longitude between -180 and 180),
  constraint providers_statut_check     check (statut_validation in ('pending', 'approved', 'rejected'))
);

-- 4. Table des événements de mission si elle n'existe pas
create table if not exists public.mission_events (
  id         bigint generated always as identity primary key,
  mission_id uuid not null,
  actor_id   uuid references public.profiles (id) on delete set null,
  kind       text not null,
  payload    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- 5. Table des signalements si elle n'existe pas
create table if not exists public.provider_reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id),
  provider_id uuid not null references public.providers (id),
  mission_id  uuid,
  motif       text not null,
  details     text,
  status      text not null default 'open' check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  admin_note  text,
  resolved_by uuid references public.profiles (id),
  resolved_at timestamptz,
  created_at  timestamptz not null default now()
);

-- 6. Table des missions sécurisée avec toutes les colonnes nécessaires
create table if not exists public.missions (
  id               uuid primary key default gen_random_uuid(),
  client_id        uuid not null references public.profiles (id) on delete cascade,
  provider_id      uuid not null references public.providers (id) on delete cascade,
  vehicle_type     text not null check (vehicle_type in ('moto', 'voiture', 'camion')),
  problem          text not null check (length(btrim(problem)) between 3 and 300),
  description      text,
  client_lat       double precision not null check (client_lat between -90 and 90),
  client_lng       double precision not null check (client_lng between -180 and 180),
  client_address   text,
  status           text not null default 'pending'
    check (status in ('pending', 'accepted', 'arrived', 'working', 'completed', 'cancelled', 'refused')),
  distance_km      numeric(7, 2) not null default 0,
  travel_fee_fcfa  integer not null default 0 check (travel_fee_fcfa >= 0),
  repair_fee_fcfa  integer not null default 0 check (repair_fee_fcfa >= 0),
  paid_fcfa        integer not null default 0 check (paid_fcfa >= 0),
  provider_lat     double precision,
  provider_lng     double precision,
  provider_pos_at  timestamptz,
  accepted_at      timestamptz,
  arrived_at       timestamptz,
  work_started_at  timestamptz,
  work_ended_at    timestamptz,
  cancelled_at     timestamptz,
  cancel_reason    text,
  travel_fee_paid  boolean not null default false,
  prank_reported   boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index if not exists idx_missions_client   on public.missions (client_id, created_at desc);
create index if not exists idx_missions_provider on public.missions (provider_id, created_at desc);
create index if not exists idx_missions_status   on public.missions (status, created_at desc);

-- 7. Fonction utilitaire de journalisation d'événements si manquante
create or replace function public.log_mission_event(p_mission uuid, p_kind text, p_payload jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = ''
as $$
  insert into public.mission_events (mission_id, actor_id, kind, payload)
  values (p_mission, (select pr.id from public.profiles pr where pr.id = (select auth.uid())),
          p_kind, coalesce(p_payload, '{}'::jsonb));
$$;

-- 8. Fonction de création de mission
create or replace function public.create_mission(
  p_provider uuid, p_vehicle text, p_problem text, p_description text,
  p_lat double precision, p_lng double precision, p_address text default null
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_pv   public.providers%rowtype;
  v_km   numeric;
  v_fee  integer;
  v_id   uuid;
  v_name text;
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  if p_provider = v_uid then raise exception 'PRESTATAIRE_INTROUVABLE' using errcode = 'P0002'; end if;
  
  select * into v_pv from public.providers pv
   where pv.id = p_provider and pv.statut_validation = 'approved' and pv.fin_abonnement > now();
  if not found then raise exception 'PRESTATAIRE_INTROUVABLE' using errcode = 'P0002'; end if;

  v_km  := round((public.haversine_km(p_lat, p_lng, v_pv.latitude, v_pv.longitude) * 1.25)::numeric, 2);
  v_fee := greatest((ceil(v_km * v_pv.tarif_km_fcfa / 50.0))::integer * 50, v_pv.frais_deplacement_min_fcfa);

  insert into public.missions
    (client_id, provider_id, vehicle_type, problem, description, client_lat, client_lng,
     client_address, distance_km, travel_fee_fcfa, travel_fee_paid, status)
  values
    (v_uid, p_provider, p_vehicle, btrim(p_problem), left(nullif(btrim(p_description), ''), 500),
     p_lat, p_lng, left(nullif(btrim(p_address), ''), 300), v_km, v_fee, false, 'pending')
  returning id into v_id;

  select coalesce(nullif(btrim(coalesce(c.first_name, '') || ' ' || coalesce(c.last_name, '')), ''), 'Un client')
    into v_name from public.profiles c where c.id = v_uid;

  perform public.log_mission_event(v_id, 'created',
    jsonb_build_object('problem', btrim(p_problem), 'distance_km', v_km, 'travel_fee_fcfa', v_fee));
    
  return v_id;
end;
$$;

-- 9. Validation du paiement des frais de déplacement
create or replace function public.pay_mission_travel_fee(p_mission uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_m   public.missions%rowtype;
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  select * into v_m from public.missions mi where mi.id = p_mission and mi.client_id = v_uid for update;
  if not found then raise exception 'INTROUVABLE' using errcode = 'P0002'; end if;

  update public.missions set travel_fee_paid = true, paid_fcfa = paid_fcfa + travel_fee_fcfa where id = v_m.id;
  
  perform public.log_mission_event(v_m.id, 'travel_fee_paid', jsonb_build_object('amount', v_m.travel_fee_fcfa));
end;
$$;

-- 10. Gestion du signalement de canulard
create or replace function public.report_mission_prank(p_mission uuid, p_details text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_m   public.missions%rowtype;
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  select * into v_m from public.missions mi where mi.id = p_mission and mi.provider_id = v_uid for update;
  if not found then raise exception 'INTROUVABLE' using errcode = 'P0002'; end if;

  update public.missions
     set status = 'cancelled', prank_reported = true, cancel_reason = 'Canulard / Client absent'
   where id = v_m.id;

  insert into public.provider_reports (reporter_id, provider_id, mission_id, motif, details, status)
  values (v_uid, v_uid, v_m.id, 'fausse_arrivee', coalesce(p_details, 'Client injoignable ou canulard sur les lieux'), 'open');
end;
$$;

commit;