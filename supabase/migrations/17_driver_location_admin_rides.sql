-- =============================================================================
-- MONTOTEM : Script 17 - Position du conducteur en direct, courses côté admin
-- Fichier  : sql/17_driver_location_admin_rides.sql
-- Prérequis : scripts 01b à 16 exécutés. Idempotent.
-- =============================================================================
begin;

set local search_path to public, extensions;

alter table public.providers
  add column if not exists location_updated_at timestamptz;

-- -----------------------------------------------------------------------------
-- 1. Position du conducteur (réservée aux transporteurs : la position d'un
--    dépanneur est celle de son garage et ne doit jamais être écrasée).
--    Le trigger trg_providers_sync_location met à jour la colonne géographique.
-- -----------------------------------------------------------------------------
create or replace function public.update_driver_location(
  p_lat double precision,
  p_lng double precision
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_pv  public.providers%rowtype;
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;
  if p_lat is null or p_lng is null
     or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'POSITION_INVALIDE' using errcode = '22023';
  end if;

  select * into v_pv from public.providers where id = v_uid for update;
  if not found then
    raise exception 'PAS_PRESTATAIRE' using errcode = 'P0002';
  end if;
  if v_pv.provider_kind is null
     or v_pv.provider_kind not in ('zemidjan', 'tricycle_fret') then
    raise exception 'SERVICE_INCOMPATIBLE' using errcode = 'P0001';
  end if;

  -- Au plus une mise à jour toutes les 15 secondes.
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

-- -----------------------------------------------------------------------------
-- 2. Courses côté administrateur
-- -----------------------------------------------------------------------------
-- Liste des courses. Les demandes restées sans conducteur plus de 30 minutes
-- sont d'abord annulées, pour qu'aucune demande fantôme ne reste « en cours ».
create or replace function public.admin_rides(p_limit integer default 150)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r     public.rides%rowtype;
  v_out jsonb := '[]'::jsonb;
begin
  if not public.is_admin() then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;

  update public.rides
     set status = 'cancelled', cancelled_at = now(),
         cancel_reason = 'Aucun conducteur disponible'
   where status = 'requested' and created_at < now() - interval '30 minutes';

  for r in
    select * from public.rides
     order by created_at desc
     limit least(greatest(coalesce(p_limit, 150), 1), 500)
  loop
    v_out := v_out || jsonb_build_array(public.ride_build_json(r, auth.uid(), true));
  end loop;

  return v_out;
end;
$$;

create or replace function public.admin_cancel_ride(
  p_ride   uuid,
  p_reason text
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_r      public.rides%rowtype;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  if not public.is_admin() then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;
  if char_length(v_reason) < 3 then
    raise exception 'MOTIF_OBLIGATOIRE' using errcode = '22023';
  end if;

  select * into v_r from public.rides where id = p_ride for update;
  if not found then
    raise exception 'INTROUVABLE' using errcode = 'P0002';
  end if;
  if v_r.status in ('completed', 'cancelled') then
    raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
  end if;

  update public.rides
     set status = 'cancelled', cancelled_at = now(), cancelled_by = auth.uid(),
         cancel_reason = left(v_reason, 300)
   where id = v_r.id;

  perform public.safe_notify(v_r.client_id, 'ride_cancelled', 'Course annulée',
    'Course annulée par MONTOTEM : ' || left(v_reason, 120),
    jsonb_build_object('ride_id', v_r.id));
  if v_r.provider_id is not null then
    perform public.safe_notify(v_r.provider_id, 'ride_cancelled', 'Course annulée',
      'Course annulée par MONTOTEM : ' || left(v_reason, 120),
      jsonb_build_object('ride_id', v_r.id));
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- 3. Droits d'exécution
-- -----------------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('update_driver_location', 'admin_rides', 'admin_cancel_ride')
  loop
    execute format('revoke all on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;
end $$;

commit;