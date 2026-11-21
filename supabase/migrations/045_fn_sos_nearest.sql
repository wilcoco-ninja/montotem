-- =============================================================================
-- 045 — SOS express : prestataires proches + carte + vehicle_map
-- Dart : sos_express.dart, guest_map_screen.dart, map_home_screen.dart
-- Dépend de : 013, 019
-- =============================================================================
begin;

set local search_path to public, extensions;

-- Bandeau SOS 1-clic
create or replace function public.providers_nearest(
  p_lat double precision, p_lng double precision,
  p_kind text default null, p_vehicle text default null,
  p_radius_km numeric default 3, p_limit integer default 3
) returns table (
  id uuid, nom text, metier text, provider_kind text,
  latitude double precision, longitude double precision,
  distance_m integer, eta_min integer, travel_fee_fcfa integer,
  telephone text, note_moyenne numeric, disponible boolean
)
language sql stable security definer set search_path = public, extensions
as $$
  with me as (
    select st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography as g
  )
  select pv.id,
         coalesce(nullif(btrim(pv.business_name), ''),
                  nullif(btrim(coalesce(pf.first_name, '') || ' ' || coalesce(pf.last_name, '')), ''),
                  'Prestataire') as nom,
         pv.metier, pv.provider_kind,
         pv.latitude, pv.longitude,
         round(d.m)::integer as distance_m,
         greatest(ceil(d.m * 1.25 / 1000.0 / 25.0 * 60.0)::integer, 1) as eta_min,
         greatest(ceil(d.m / 1000.0 * coalesce(pv.tarif_km_fcfa, 0) / 50.0)::integer * 50,
                  coalesce(pv.frais_deplacement_min_fcfa, 0)) as travel_fee_fcfa,
         case when auth.uid() is not null then pf.phone end as telephone,
         pv.note_moyenne, pv.disponible
    from public.providers pv
    join public.profiles  pf on pf.id = pv.id
   cross join me
   cross join lateral (select st_distance(pv.location, me.g) as m) d
   where pv.statut_validation = 'approved'
     and pv.disponible
     and pv.location is not null
     and not pf.is_suspended
     and not exists (select 1 from public.wallets w
                      where w.provider_id = pv.id and w.blocked)
     and (p_kind is null or pv.provider_kind = p_kind)
     and (p_vehicle is null
          or pv.provider_kind in ('zemidjan','tricycle_passenger','tricycle_fret')
          or coalesce(cardinality(pv.vehicle_types), 0) = 0
          or p_vehicle = any (pv.vehicle_types))
     and d.m <= least(greatest(coalesce(p_radius_km, 3), 0.1), 50) * 1000
     and d.m <= coalesce(pv.rayon_max_km, 50) * 1000
   order by d.m
   limit least(greatest(coalesce(p_limit, 3), 1), 40);
$$;
revoke all on function public.providers_nearest(
  double precision, double precision, text, text, numeric, integer) from public;
grant execute on function public.providers_nearest(
  double precision, double precision, text, text, numeric, integer)
  to anon, authenticated;

-- Carte : prestataires dans une bounding box (dépannage, hors transporteurs)
create or replace function public.providers_in_bounds(
  p_min_lat double precision, p_min_lng double precision,
  p_max_lat double precision, p_max_lng double precision,
  p_limit integer default 400
) returns table (
  id uuid, nom text, metier text,
  latitude double precision, longitude double precision,
  telephone text, photo_url text, business_name text, adresse text,
  verifie boolean, disponible boolean, note_moyenne numeric,
  clients_satisfaits integer, clients_insatisfaits integer,
  missions_completees integer, statut_mission text, vehicle_types text[]
)
language sql stable security definer set search_path = public, extensions
as $$
  select pv.id,
         coalesce(nullif(btrim(coalesce(pf.first_name, '') || ' ' || coalesce(pf.last_name, '')), ''),
                  'Prestataire'),
         pv.metier, pv.latitude, pv.longitude,
         case when auth.uid() is not null then pf.phone end,
         pf.photo_profil_url, pv.business_name, pv.ville, true,
         pv.disponible, pv.note_moyenne,
         pv.clients_satisfaits, pv.clients_insatisfaits,
         pv.missions_completees, pv.statut_mission, pv.vehicle_types
    from public.providers pv
    join public.profiles  pf on pf.id = pv.id
   where pv.statut_validation = 'approved'
     and not pf.is_suspended
     and coalesce(pv.provider_kind, '') not in ('zemidjan','tricycle_passenger','tricycle_fret')
     and pv.latitude between p_min_lat and p_max_lat
     and case when p_min_lng <= p_max_lng
              then pv.longitude between p_min_lng and p_max_lng
              else (pv.longitude >= p_min_lng or pv.longitude <= p_max_lng) end
   order by pv.note_moyenne desc
   limit least(greatest(coalesce(p_limit, 400), 1), 2000);
$$;
revoke all on function public.providers_in_bounds(
  double precision, double precision, double precision, double precision, integer) from public;
grant execute on function public.providers_in_bounds(
  double precision, double precision, double precision, double precision, integer)
  to anon, authenticated;

-- Filtres carte : types de véhicules par prestataire
create or replace function public.provider_vehicle_map()
returns table (provider_id uuid, vehicle_types text[])
language sql stable security definer set search_path = public, extensions
as $$
  select pv.id, pv.vehicle_types
    from public.providers pv
    join public.profiles pf on pf.id = pv.id
   where pv.statut_validation = 'approved'
     and not pf.is_suspended;
$$;
revoke all on function public.provider_vehicle_map() from public;
grant execute on function public.provider_vehicle_map() to anon, authenticated;

commit;