-- =============================================================================
-- 016 — Missions de dépannage (catalogue figé)
-- Dart : mission_service.dart, mission_model.dart, mission_item_model.dart,
--        mission_payment_model.dart
-- Dépend de : 013, 014, 015
-- =============================================================================
begin;

set local search_path to public, extensions;

-- Dart : Mission.fromJson (id, status, vehicle_type, problem,
--        travel_fee_fcfa, repair_fee_fcfa, paid_fcfa, ...)
create table if not exists public.missions (
  id               uuid primary key default gen_random_uuid(),
  client_id        uuid not null references public.profiles(id) on delete cascade,
  provider_id      uuid not null references public.providers(id) on delete cascade,
  vehicle_type     text not null check (vehicle_type in
                     ('moto','tricycle','voiture','bus','camion')),
  problem          text not null check (length(btrim(problem)) between 3 and 300),
  description      text,
  client_lat       double precision not null check (client_lat between -90 and 90),
  client_lng       double precision not null check (client_lng between -180 and 180),
  client_address   text,
  status           text not null default 'pending'
                   check (status in ('pending','accepted','arrived','working',
                                     'completed','cancelled','refused')),
  distance_km      numeric(7,2) not null default 0,
  travel_fee_fcfa  integer not null default 0 check (travel_fee_fcfa >= 0),
  repair_fee_fcfa  integer not null default 0 check (repair_fee_fcfa >= 0),
  paid_fcfa        integer not null default 0 check (paid_fcfa >= 0),
  travel_fee_paid  boolean not null default false,
  prank_reported   boolean not null default false,
  reviewed         boolean not null default false,
  provider_lat     double precision,
  provider_lng     double precision,
  provider_pos_at  timestamptz,
  accepted_at      timestamptz,
  arrived_at       timestamptz,
  work_started_at  timestamptz,
  work_ended_at    timestamptz,
  cancelled_at     timestamptz,
  cancel_reason    text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists idx_missions_client   on public.missions (client_id, created_at desc);
create index if not exists idx_missions_provider on public.missions (provider_id, created_at desc);
create index if not exists idx_missions_status   on public.missions (status, created_at desc);

drop trigger if exists trg_missions_updated_at on public.missions;
create trigger trg_missions_updated_at
  before update on public.missions
  for each row execute function public.set_updated_at();

-- Dart : MissionItem.fromJson (id, nom, prix_fcfa)
create table if not exists public.mission_items (
  id              uuid primary key default gen_random_uuid(),
  mission_id      uuid not null references public.missions(id) on delete cascade,
  catalog_item_id uuid references public.provider_catalog_items(id) on delete set null,
  nom             text not null,
  prix_fcfa       integer not null check (prix_fcfa > 0),
  created_at      timestamptz not null default now()
);
create index if not exists idx_mission_items_mission
  on public.mission_items (mission_id);

-- Journal
create table if not exists public.mission_events (
  id         bigint generated always as identity primary key,
  mission_id uuid not null references public.missions(id) on delete cascade,
  actor_id   uuid references public.profiles(id) on delete set null,
  kind       text not null,
  payload    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists idx_mission_events_mission
  on public.mission_events (mission_id, created_at);

-- Dart : MissionPayment.fromJson (kind, amount_fcfa, methode, status, ...)
create table if not exists public.mission_payments (
  id            uuid primary key default gen_random_uuid(),
  mission_id    uuid not null references public.missions(id) on delete cascade,
  kind          text not null check (kind in ('trajet','reparation')),
  amount_fcfa   integer not null check (amount_fcfa > 0),
  operateur     text not null check (operateur in ('mtn','moov','celtiis','especes')),
  payer_phone   text,
  reference     text,
  confirmed_at  timestamptz,
  rejected_at   timestamptz,
  reject_reason text,
  created_at    timestamptz not null default now()
);
create index if not exists idx_mission_payments_mission
  on public.mission_payments (mission_id, created_at);

-- Chat
create table if not exists public.mission_messages (
  id         uuid primary key default gen_random_uuid(),
  mission_id uuid not null references public.missions(id) on delete cascade,
  sender_id  uuid not null references public.profiles(id) on delete cascade,
  body       text not null check (char_length(btrim(body)) between 1 and 500),
  created_at timestamptz not null default now()
);
create index if not exists idx_mission_messages_mission
  on public.mission_messages (mission_id, created_at);

-- Avis
create table if not exists public.mission_reviews (
  id          uuid primary key default gen_random_uuid(),
  mission_id  uuid not null unique references public.missions(id) on delete cascade,
  client_id   uuid not null references public.profiles(id) on delete cascade,
  provider_id uuid not null references public.providers(id) on delete cascade,
  stars       integer not null check (stars between 1 and 5),
  comment     text,
  created_at  timestamptz not null default now()
);
create index if not exists idx_mission_reviews_provider
  on public.mission_reviews (provider_id, created_at desc);

-- Points d'étoiles
create table if not exists public.star_points_ledger (
  id         bigint generated always as identity primary key,
  client_id  uuid not null references public.profiles(id) on delete cascade,
  mission_id uuid references public.missions(id) on delete set null,
  delta      integer not null,
  reason     text not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_star_points_client
  on public.star_points_ledger (client_id, created_at desc);

commit;