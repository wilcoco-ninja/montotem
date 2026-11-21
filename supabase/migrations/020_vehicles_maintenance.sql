-- =============================================================================
-- 020 — Carnet d'entretien (optionnel, aucune dépendance Dart pour l'instant)
-- Dépend de : 010
-- =============================================================================
begin;

set local search_path to public, extensions;

create table if not exists public.vehicles (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  kind       text not null check (kind in ('moto','tricycle','voiture','bus','camion')),
  plaque     text,
  marque     text,
  km_actuel  integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.maintenance_rules (
  id         uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  label      text not null,
  every_km   integer,
  every_days integer,
  last_km    integer not null default 0,
  last_date  date not null default current_date
);

commit;