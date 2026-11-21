-- =============================================================================
-- 017 — Courses : 3 service_kind (zemidjan, tricycle_passenger, tricycle_fret)
-- Dart : ride_service.dart, ride_model.dart
-- Dépend de : 013, 015
-- =============================================================================
begin;

set local search_path to public, extensions;

-- Dart : Ride.fromJson (service_kind ∈ 3 valeurs)
create table if not exists public.rides (
  id                 uuid primary key default gen_random_uuid(),
  client_id          uuid not null references public.profiles(id) on delete cascade,
  provider_id        uuid references public.providers(id) on delete set null,
  service_kind       text not null check (service_kind in
                     ('zemidjan','tricycle_passenger','tricycle_fret')),
  status             text not null default 'requested'
                     check (status in ('requested','accepted','arrived',
                                       'in_progress','completed','cancelled')),
  pickup             geography(Point, 4326) not null,
  dropoff            geography(Point, 4326) not null,
  pickup_address     text,
  dropoff_address    text,
  distance_m         integer not null default 0 check (distance_m >= 0),
  fare_fcfa          integer not null check (fare_fcfa between 100 and 500000),
  final_fare_fcfa    integer check (final_fare_fcfa is null
                                   or final_fare_fcfa between 100 and 500000),
  payment_method     text not null default 'cash'
                     check (payment_method in ('cash','mtn','moov','celtiis')),
  commission_fcfa    integer not null default 0 check (commission_fcfa >= 0),
  commission_pct     numeric(5,2) not null default 0,
  commission_applied boolean not null default false,
  cancel_reason      text,
  cancelled_by       uuid references public.profiles(id) on delete set null,
  provider_lat       double precision,
  provider_lng       double precision,
  provider_pos_at    timestamptz,
  accepted_at        timestamptz,
  arrived_at         timestamptz,
  started_at         timestamptz,
  completed_at       timestamptz,
  cancelled_at       timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint rides_provider_not_client check
    (provider_id is null or provider_id <> client_id)
);
create index if not exists idx_rides_client   on public.rides (client_id, created_at desc);
create index if not exists idx_rides_provider on public.rides (provider_id, created_at desc);
create index if not exists idx_rides_open     on public.rides (service_kind, created_at desc)
  where status = 'requested';
create index if not exists idx_rides_pickup   on public.rides using gist (pickup);

drop trigger if exists trg_rides_updated_at on public.rides;
create trigger trg_rides_updated_at
  before update on public.rides
  for each row execute function public.set_updated_at();

commit;