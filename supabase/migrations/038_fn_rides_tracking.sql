-- =============================================================================
-- 038 — Tracking GPS courses + position conducteur + courses proches
-- Dart : ride_service.dart, ride_driver_service.dart,
--        provider_ride_screen.dart, provider_rides_screen.dart
-- Dépend de : 017
-- =============================================================================
begin;

set local search_path to public, extensions;

-- GPS course
create or replace function public.update_ride_provider_position(
  p_ride uuid, p_lat double precision, p_lng double precision
) returns text
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_r   public.rides%rowtype;
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  if p_lat is null or p_lng is null
     or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'POSITION_INCONNUE' using errcode = '22023';
  end if;
  select * into v_r from public.rides
   where id = p_ride and provider_id = v_uid for update;
  if not found then raise exception 'INTROUVABLE' using errcode = 'P0002'; end if;
  if v_r.status not in ('accepted','arrived','in_progress') then
    return v_r.status;
  end if;
  update public.rides
     set provider_lat = p_lat, provider_lng = p_lng, provider_pos_at = now()
   where id = v_r.id;
  return v_r.status;
end;
$$;
revoke all on function public.update_ride_provider_position(uuid, double precision, double precision)
  from public, anon;
grant execute on function public.update_ride_provider_position(uuid, double precision, double precision)
  to authenticated;

-- Position "connexion" du conducteur (hors course)
create or replace function public.update_driver_location(
  p_lat double precision, p_lng double precision
) returns boolean
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_pv  public.providers%rowtype;
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  if p_lat is null or p_lng is null
     or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'POSITION_INVALIDE' using errcode = '22023';
  end if;
  select * into v_pv from public.providers where id = v_uid for update;
  if not found then raise exception 'PAS_PRESTATAIRE' using errcode = 'P0002'; end if;
  if v_pv.provider_kind is null
     or v_pv.provider_kind not in ('zemidjan','tricycle_passenger','tricycle_fret') then
    raise exception 'SERVICE_INCOMPATIBLE' using errcode = 'P0001';
  end if;
  if v_pv.location_updated_at is not null
     and v_pv.location_updated_at > now() - interval '15 seconds' then
    return false;
  end if;
  update public.providers
     set latitude = p_lat, longitude = p_lng, location_updated_at = now()
   where id = v_uid;
  return true;
end;
$$;
revoke all on function public.update_driver_location(double precision, double precision)
  from public, anon;
grant execute on function public.update_driver_location(double precision, double precision)
  to authenticated;

-- Courses proches (filtrées par kind du conducteur)
create or replace function public.rides_nearby(
  p_lat double precision, p_lng double precision, p_radius_km numeric default 5
) returns table (
  id                     uuid,
  service_kind           text,
  pickup_address         text,
  dropoff_address        text,
  fare_fcfa              integer,
  payment_method         text,
  distance_to_pickup_m   integer,
  trip_distance_m        integer,
  created_at             timestamptz
)
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_kind text;
  v_blocked boolean;
  v_user_location geography;
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  select blocked into v_blocked from public.wallets where provider_id = v_uid;
  if coalesce(v_blocked, false) then return; end if;
  select provider_kind into v_kind from public.providers where id = v_uid;
  if v_kind is null or v_kind not in ('zemidjan','tricycle_passenger','tricycle_fret') then
    return;
  end if;

  v_user_location := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;

  return query
  select r.id, r.service_kind, r.pickup_address, r.dropoff_address,
         r.fare_fcfa, r.payment_method,
         round(st_distance(r.pickup, v_user_location))::integer,
         r.distance_m, r.created_at
  from public.rides r
  where r.status = 'requested'
    and r.service_kind = v_kind
    and st_dwithin(r.pickup, v_user_location, p_radius_km * 1000)
  order by st_distance(r.pickup, v_user_location) asc;
end;
$$;
revoke all on function public.rides_nearby(double precision, double precision, numeric)
  from public, anon;
grant execute on function public.rides_nearby(double precision, double precision, numeric)
  to authenticated;

commit;