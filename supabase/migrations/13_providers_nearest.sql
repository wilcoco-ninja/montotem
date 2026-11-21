-- =============================================================================
-- MONTOTEM : 13 - Prestataires les plus proches (bandeau 1-clic + « JE SUIS EN PANNE »)
-- A exécuter après les scripts 07 (PostGIS, provider_kind, location) et 08.
-- Ne modifie aucune table : crée seulement une fonction.
-- =============================================================================
begin;

-- Ancienne version proposée dans le chat (signature différente) : on la retire.
drop function if exists public.providers_nearest(
  double precision, double precision, text, numeric, integer);

create or replace function public.providers_nearest(
  p_lat       double precision,
  p_lng       double precision,
  p_kind      text    default null,   -- mecanicien | vulcanisateur | electricien | station | garage | zemidjan
  p_vehicle   text    default null,   -- moto | voiture | camion
  p_radius_km numeric default 3,
  p_limit     integer default 3
) returns table (
  id              uuid,
  nom             text,
  metier          text,
  provider_kind   text,
  latitude        double precision,
  longitude       double precision,
  distance_m      integer,
  eta_min         integer,
  travel_fee_fcfa integer,
  telephone       text,
  note_moyenne    numeric,
  disponible      boolean
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with me as (
    select ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography as g
  )
  select pv.id,
         coalesce(nullif(btrim(pv.business_name), ''),
                  nullif(btrim(coalesce(pf.first_name, '') || ' ' || coalesce(pf.last_name, '')), ''),
                  'Prestataire')                                           as nom,
         pv.metier,
         pv.provider_kind,
         pv.latitude,
         pv.longitude,
         round(d.m)::integer                                               as distance_m,
         -- Trajet estimé : détour de 25 % sur la ligne droite, 25 km/h en ville.
         greatest(ceil(d.m * 1.25 / 1000.0 / 25.0 * 60.0)::integer, 1)     as eta_min,
         -- Même règle que TravelFee.estimate (Flutter) : max(minimum, km × tarif), arrondi à 50 FCFA.
         greatest(ceil(d.m / 1000.0 * coalesce(pv.tarif_km_fcfa, 0) / 50.0)::integer * 50,
                  coalesce(pv.frais_deplacement_min_fcfa, 0))              as travel_fee_fcfa,
         -- Le numéro n'est donné qu'aux utilisateurs connectés.
         case when auth.uid() is not null then pf.phone end                as telephone,
         pv.note_moyenne,
         pv.disponible
    from public.providers pv
    join public.profiles  pf on pf.id = pv.id
   cross join me
   cross join lateral (select ST_Distance(pv.location, me.g) as m) d
   where pv.statut_validation = 'approved'
     and pv.fin_abonnement > now()
     and pv.disponible
     and pv.location is not null
     and not pf.is_suspended
     and not exists (select 1 from public.wallets w
                      where w.provider_id = pv.id and w.blocked)
     and (p_kind is null or pv.provider_kind = p_kind)
     -- Un zémidjan est forcément une moto ; pour les autres, une liste vide = tous véhicules.
     and (p_vehicle is null
          or pv.provider_kind = 'zemidjan'
          or coalesce(cardinality(pv.vehicle_types), 0) = 0
          or p_vehicle = any (pv.vehicle_types))
     -- Distance demandée par le client ET rayon maximal accepté par le prestataire.
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

commit;