-- =============================================================================
-- 019 — Règles de commission (fixées par l'admin, différenciées par service)
-- Dart : admin_commission_service.dart
-- Dépend de : 010
-- RÈGLE : l'admin fixe le % par catégorie. Le prestataire fixe SES prix
--         de main d'œuvre dans le catalogue. Aucun abonnement.
-- =============================================================================
begin;

set local search_path to public, extensions;

create table if not exists public.commission_rules (
  id               uuid primary key default gen_random_uuid(),
  service_category text not null check (service_category in (
    -- 3 types de courses
    'ride_zemidjan',              -- moto 1 passager
    'ride_tricycle_passenger',    -- kloboto 2-3 personnes
    'ride_tricycle_fret',         -- kloboto colis/bagages
    -- 5 types de dépannage (par véhicule)
    'mission_moto',
    'mission_tricycle',
    'mission_voiture',
    'mission_bus',
    'mission_camion',
    -- Remorquage (garage uniquement)
    'mission_remorquage'
  )),
  provider_kind    text,
  vehicle_type     text,
  pct              numeric(5,2) not null check (pct between 0 and 100),
  actif            boolean not null default true,
  note             text,
  updated_by       uuid references public.profiles(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create unique index if not exists uq_commission_rules_active
  on public.commission_rules (
    service_category,
    coalesce(provider_kind, ''),
    coalesce(vehicle_type, '')
  )
  where actif;

create index if not exists idx_commission_rules_service
  on public.commission_rules (service_category, actif);

drop trigger if exists trg_commission_rules_updated_at on public.commission_rules;
create trigger trg_commission_rules_updated_at
  before update on public.commission_rules
  for each row execute function public.set_updated_at();

-- Valeurs par défaut (modifiables par l'admin via admin_upsert_commission_rule)
insert into public.commission_rules (service_category, provider_kind, vehicle_type, pct, note)
values
  ('ride_zemidjan',            'zemidjan',           null, 15, 'Moto 1 passager'),
  ('ride_tricycle_passenger',  'tricycle_passenger', null, 12, 'Tricycle 2-3 passagers'),
  ('ride_tricycle_fret',       'tricycle_fret',      null, 15, 'Tricycle colis/bagages'),
  ('mission_moto',             null, 'moto',          10, 'Dépannage moto'),
  ('mission_tricycle',         null, 'tricycle',      12, 'Dépannage tricycle'),
  ('mission_voiture',          null, 'voiture',       12, 'Dépannage voiture'),
  ('mission_bus',              null, 'bus',           10, 'Dépannage bus'),
  ('mission_camion',           null, 'camion',        10, 'Dépannage camion'),
  ('mission_remorquage',       'garage', null,         8, 'Remorquage garage → atelier')
on conflict (service_category, coalesce(provider_kind, ''), coalesce(vehicle_type, ''))
  where actif
do nothing;

-- RPC utilisée en interne par rides_apply_commission et apply_travel_commission
create or replace function public.commission_pct(
  p_service_category text,
  p_provider_kind    text default null,
  p_vehicle_type     text default null
) returns numeric
language plpgsql stable security definer set search_path = public
as $$
declare v_pct numeric;
begin
  select pct into v_pct from public.commission_rules
   where actif and service_category = p_service_category
     and provider_kind = p_provider_kind
     and vehicle_type = p_vehicle_type
   limit 1;
  if v_pct is not null then return v_pct; end if;

  select pct into v_pct from public.commission_rules
   where actif and service_category = p_service_category
     and provider_kind = p_provider_kind
     and vehicle_type is null
   limit 1;
  if v_pct is not null then return v_pct; end if;

  select pct into v_pct from public.commission_rules
   where actif and service_category = p_service_category
     and provider_kind is null
     and vehicle_type = p_vehicle_type
   limit 1;
  if v_pct is not null then return v_pct; end if;

  select pct into v_pct from public.commission_rules
   where actif and service_category = p_service_category
     and provider_kind is null
     and vehicle_type is null
   limit 1;
  if v_pct is not null then return v_pct; end if;

  return 15;
end;
$$;
revoke all on function public.commission_pct(text, text, text) from public, anon;
grant execute on function public.commission_pct(text, text, text) to authenticated;

commit;