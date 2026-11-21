-- =============================================================================
-- MONTOTEM : Script 16 - Les transporteurs (Zémidjan, Tricycle Fret) sont
-- exclus de la carte et des missions de dépannage
-- Fichier  : sql/16_transport_providers.sql
-- Prérequis : scripts 01b à 15 exécutés. Idempotent.
-- =============================================================================
begin;

set local search_path to public, extensions;

-- -----------------------------------------------------------------------------
-- 1. Carte du dépannage : aucun transporteur
-- -----------------------------------------------------------------------------
create or replace function public.providers_in_bounds(
  p_min_lat double precision,
  p_min_lng double precision,
  p_max_lat double precision,
  p_max_lng double precision,
  p_limit   integer default 400
) returns table (
  id                   uuid,
  nom                  text,
  metier               text,
  latitude             double precision,
  longitude            double precision,
  telephone            text,
  photo_url            text,
  business_name        text,
  adresse              text,
  verifie              boolean,
  disponible           boolean,
  note_moyenne         numeric,
  clients_satisfaits   integer,
  clients_insatisfaits integer,
  missions_completees  integer,
  statut_mission       text,
  vehicle_types        text[]
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select pv.id,
         coalesce(nullif(btrim(coalesce(pf.first_name, '') || ' ' || coalesce(pf.last_name, '')), ''),
                  'Prestataire'),
         pv.metier,
         pv.latitude,
         pv.longitude,
         case when auth.uid() is not null then pf.phone end,
         pf.photo_profil_url,
         pv.business_name,
         pv.ville,
         true,
         pv.disponible,
         pv.note_moyenne,
         pv.clients_satisfaits,
         pv.clients_insatisfaits,
         pv.missions_completees,
         pv.statut_mission,
         pv.vehicle_types
    from public.providers pv
    join public.profiles  pf on pf.id = pv.id
   where pv.statut_validation = 'approved'
     and pv.fin_abonnement > now()
     and not pf.is_suspended
     and coalesce(pv.provider_kind, '') not in ('zemidjan', 'tricycle_fret')
     and pv.latitude between p_min_lat and p_max_lat
     and case when p_min_lng <= p_max_lng
              then pv.longitude between p_min_lng and p_max_lng
              else (pv.longitude >= p_min_lng or pv.longitude <= p_max_lng)
         end
   order by (pv.palier = 'premium') desc nulls last, pv.note_moyenne desc
   limit least(greatest(coalesce(p_limit, 400), 1), 2000);
$$;

create or replace function public.provider_vehicle_map()
returns table (provider_id uuid, vehicle_types text[])
language sql
stable
security definer
set search_path = public, extensions
as $$
  select pv.id, pv.vehicle_types
    from public.providers pv
    join public.profiles  pf on pf.id = pv.id
   where pv.statut_validation = 'approved'
     and pv.fin_abonnement > now()
     and not pf.is_suspended
     and coalesce(pv.provider_kind, '') not in ('zemidjan', 'tricycle_fret');
$$;

-- -----------------------------------------------------------------------------
-- 2. Missions de dépannage : refus d'un transporteur (même par appel direct)
-- -----------------------------------------------------------------------------
create or replace function public.missions_guard_provider_kind()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if exists (
    select 1 from public.providers pv
     where pv.id = new.provider_id
       and pv.provider_kind in ('zemidjan', 'tricycle_fret')
  ) then
    raise exception 'PRESTATAIRE_INTROUVABLE' using errcode = 'P0002';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_missions_guard_kind on public.missions;
create trigger trg_missions_guard_kind
  before insert on public.missions
  for each row execute function public.missions_guard_provider_kind();

commit;