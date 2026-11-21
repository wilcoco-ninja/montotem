-- =============================================================================
-- 002 — Fonctions utilitaires (helpers)
-- Dart : (aucun, utilisé en interne)
-- Dépend de : 001
-- =============================================================================
begin;

set local search_path to public, extensions;

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

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end;
$$;

commit;