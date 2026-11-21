-- =============================================================================
-- MONTOTEM : Script 14 - Courses : suivi GPS, détail, historique, notifications
-- Fichier  : sql/14_rides_tracking.sql
-- Prérequis : scripts 01b à 13 exécutés. Idempotent.
-- =============================================================================
begin;

set local search_path to public, extensions;

-- -----------------------------------------------------------------------------
-- 1. Position GPS du conducteur pendant la course
-- -----------------------------------------------------------------------------
alter table public.rides
  add column if not exists provider_lat    double precision,
  add column if not exists provider_lng    double precision,
  add column if not exists provider_pos_at timestamptz;

-- -----------------------------------------------------------------------------
-- 2. JSON d'une course pour l'application (masquage selon le rôle du lecteur)
-- -----------------------------------------------------------------------------
create or replace function public.ride_build_json(
  r        public.rides,
  p_viewer uuid,
  p_admin  boolean
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_reveal      boolean := p_admin or r.status in ('accepted', 'arrived', 'in_progress', 'completed');
  v_is_client   boolean := (p_viewer = r.client_id);
  v_is_provider boolean := (p_viewer = r.provider_id);
  v_cl    public.profiles%rowtype;
  v_pf    public.profiles%rowtype;
  v_pv    public.providers%rowtype;
  v_cname text;
  v_pname text;
  v_momo  jsonb := null;
begin
  select * into v_cl from public.profiles  where id = r.client_id;
  select * into v_pf from public.profiles  where id = r.provider_id;
  select * into v_pv from public.providers where id = r.provider_id;

  v_cname := coalesce(
    nullif(btrim(coalesce(v_cl.first_name, '') || ' ' || coalesce(v_cl.last_name, '')), ''),
    'Client');
  v_pname := coalesce(
    nullif(btrim(v_pv.business_name), ''),
    nullif(btrim(coalesce(v_pf.first_name, '') || ' ' || coalesce(v_pf.last_name, '')), ''),
    'Conducteur');

  -- Numéro MoMo du conducteur : uniquement pour le client, après acceptation,
  -- et seulement s'il correspond à l'opérateur choisi.
  if v_reveal
     and r.payment_method <> 'cash'
     and v_pv.momo_numero is not null
     and v_pv.momo_operateur = r.payment_method
     and (p_admin or v_is_client) then
    v_momo := jsonb_build_object(
      'operateur', v_pv.momo_operateur,
      'numero',    v_pv.momo_numero,
      'titulaire', v_pv.momo_titulaire);
  end if;

  return jsonb_build_object(
    'id',              r.id,
    'status',          r.status,
    'service_kind',    r.service_kind,
    'payment_method',  r.payment_method,
    'client_id',       r.client_id,
    'provider_id',     r.provider_id,
    'fare_fcfa',       r.fare_fcfa,
    'final_fare_fcfa', r.final_fare_fcfa,
    'commission_fcfa', case when p_admin or v_is_provider then r.commission_fcfa else null end,
    'distance_m',      r.distance_m,
    'pickup_lat',      st_y(r.pickup::geometry),
    'pickup_lng',      st_x(r.pickup::geometry),
    'dropoff_lat',     st_y(r.dropoff::geometry),
    'dropoff_lng',     st_x(r.dropoff::geometry),
    'pickup_address',  r.pickup_address,
    'dropoff_address', r.dropoff_address,
    'provider_lat',    r.provider_lat,
    'provider_lng',    r.provider_lng,
    'provider_pos_at', r.provider_pos_at,
    'accepted_at',     r.accepted_at,
    'arrived_at',      r.arrived_at,
    'started_at',      r.started_at,
    'completed_at',    r.completed_at,
    'cancelled_at',    r.cancelled_at,
    'cancel_reason',   r.cancel_reason,
    'created_at',      r.created_at,
    'client_name',     v_cname,
    'provider_name',   case when r.provider_id is null then null else v_pname end,
    'client_phone',    case when v_reveal and (p_admin or v_is_provider) then v_cl.phone else null end,
    'provider_phone',  case when v_reveal and (p_admin or v_is_client)   then v_pf.phone else null end,
    'provider_momo',   v_momo
  );
end;
$$;

create or replace function public.my_rides()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  r     public.rides%rowtype;
  v_out jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;

  for r in
    select * from public.rides
     where client_id = v_uid or provider_id = v_uid
     order by created_at desc
     limit 100
  loop
    v_out := v_out || jsonb_build_array(public.ride_build_json(r, v_uid, false));
  end loop;

  return v_out;
end;
$$;

create or replace function public.ride_details(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_uid   uuid := auth.uid();
  v_admin boolean := public.is_admin();
  r       public.rides%rowtype;
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;

  select * into r from public.rides where id = p_id;
  if not found or not (v_admin or r.client_id = v_uid or r.provider_id = v_uid) then
    raise exception 'INTROUVABLE' using errcode = 'P0002';
  end if;

  return public.ride_build_json(r, v_uid, v_admin);
end;
$$;

-- -----------------------------------------------------------------------------
-- 3. Position GPS du conducteur
-- -----------------------------------------------------------------------------
create or replace function public.update_ride_provider_position(
  p_ride uuid,
  p_lat  double precision,
  p_lng  double precision
) returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_r   public.rides%rowtype;
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;
  if p_lat is null or p_lng is null
     or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'POSITION_INCONNUE' using errcode = '22023';
  end if;

  select * into v_r from public.rides
   where id = p_ride and provider_id = v_uid
   for update;
  if not found then
    raise exception 'INTROUVABLE' using errcode = 'P0002';
  end if;

  if v_r.status not in ('accepted', 'arrived', 'in_progress') then
    return v_r.status;
  end if;

  update public.rides
     set provider_lat = p_lat, provider_lng = p_lng, provider_pos_at = now()
   where id = v_r.id;

  return v_r.status;
end;
$$;

-- -----------------------------------------------------------------------------
-- 4. Actions : accept | arrived | start | complete | cancel
-- -----------------------------------------------------------------------------
create or replace function public.ride_action(
  p_ride   uuid,
  p_action text,
  p_fare   integer default null,
  p_reason text    default null
) returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid   uuid := auth.uid();
  v_r     public.rides%rowtype;
  v_pv    public.providers%rowtype;
  v_dist  double precision;
  v_final integer;
  v_other uuid;
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;

  select * into v_r from public.rides where id = p_ride for update;
  if not found then
    raise exception 'INTROUVABLE' using errcode = 'P0002';
  end if;

  if p_action = 'accept' then
    if v_r.status <> 'requested' or v_r.provider_id is not null then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;
    if v_r.client_id = v_uid then
      raise exception 'INTERDIT' using errcode = '42501';
    end if;

    select * into v_pv from public.providers pv
     where pv.id = v_uid
       and pv.statut_validation = 'approved'
       and pv.fin_abonnement > now();
    if not found then
      raise exception 'PRESTATAIRE_NON_ACTIF' using errcode = 'P0001';
    end if;
    if v_pv.provider_kind is distinct from v_r.service_kind then
      raise exception 'SERVICE_INCOMPATIBLE' using errcode = 'P0001';
    end if;

    -- Course payée en Mobile Money : le conducteur doit pouvoir être payé.
    if v_r.payment_method <> 'cash'
       and (v_pv.momo_numero is null
            or v_pv.momo_operateur is distinct from v_r.payment_method) then
      raise exception 'MOMO_NON_CONFIGURE' using errcode = 'P0001';
    end if;

    -- Les gardes « wallet bloqué » et « compte suspendu » sont portées par le
    -- trigger trg_rides_guard_blocked.
    update public.rides
       set provider_id = v_uid, status = 'accepted', accepted_at = now()
     where id = v_r.id;

    perform public.safe_notify(v_r.client_id, 'ride_accepted', 'Conducteur en route',
      'Votre course a été acceptée. Suivez son arrivée en direct.',
      jsonb_build_object('ride_id', v_r.id));
    return 'accepted';

  elsif p_action in ('arrived', 'start', 'complete') then
    if v_r.provider_id is distinct from v_uid then
      raise exception 'INTERDIT' using errcode = '42501';
    end if;

    if p_action = 'arrived' then
      if v_r.status <> 'accepted' then
        raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
      end if;
      if v_r.provider_lat is null or v_r.provider_lng is null
         or v_r.provider_pos_at is null
         or v_r.provider_pos_at < now() - interval '5 minutes' then
        raise exception 'POSITION_INCONNUE' using errcode = 'P0001';
      end if;
      v_dist := st_distance(
        st_setsrid(st_makepoint(v_r.provider_lng, v_r.provider_lat), 4326)::geography,
        v_r.pickup);
      if v_dist > 500 then
        raise exception 'TROP_LOIN' using errcode = 'P0001';
      end if;

      update public.rides set status = 'arrived', arrived_at = now() where id = v_r.id;
      perform public.safe_notify(v_r.client_id, 'ride_arrived', 'Conducteur arrivé',
        'Votre conducteur est sur place.', jsonb_build_object('ride_id', v_r.id));
      return 'arrived';

    elsif p_action = 'start' then
      if v_r.status <> 'arrived' then
        raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
      end if;
      update public.rides set status = 'in_progress', started_at = now() where id = v_r.id;
      perform public.safe_notify(v_r.client_id, 'ride_started', 'Course démarrée',
        'Bonne route !', jsonb_build_object('ride_id', v_r.id));
      return 'in_progress';

    else
      if v_r.status <> 'in_progress' then
        raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
      end if;

      -- Baisse libre ; hausse limitée à +50 % du prix convenu.
      v_final := coalesce(p_fare, v_r.fare_fcfa);
      if v_final < 100 or v_final > 500000 or v_final > (v_r.fare_fcfa * 3 / 2) then
        raise exception 'TARIF_INVALIDE' using errcode = '22023';
      end if;

      -- Le trigger rides_apply_commission déduit la commission (cash).
      update public.rides
         set status = 'completed', final_fare_fcfa = v_final
       where id = v_r.id;

      perform public.safe_notify(v_r.client_id, 'ride_completed', 'Course terminée',
        'Montant : ' || v_final || ' FCFA.', jsonb_build_object('ride_id', v_r.id));
      return 'completed';
    end if;

  elsif p_action = 'cancel' then
    if v_uid not in (v_r.client_id, coalesce(v_r.provider_id, v_r.client_id)) then
      raise exception 'INTERDIT' using errcode = '42501';
    end if;
    if v_r.status in ('completed', 'cancelled', 'in_progress') then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;

    update public.rides
       set status = 'cancelled', cancelled_at = now(), cancelled_by = v_uid,
           cancel_reason = left(nullif(btrim(p_reason), ''), 300)
     where id = v_r.id;

    v_other := case when v_uid = v_r.client_id then v_r.provider_id else v_r.client_id end;
    if v_other is not null then
      perform public.safe_notify(v_other, 'ride_cancelled', 'Course annulée',
        'La course a été annulée.', jsonb_build_object('ride_id', v_r.id));
    end if;
    return 'cancelled';
  end if;

  raise exception 'ACTION_INVALIDE' using errcode = '22023';
end;
$$;

-- -----------------------------------------------------------------------------
-- 5. Création d'une course : expiration des anciennes demandes + alerte
--    des conducteurs proches
-- -----------------------------------------------------------------------------
create or replace function public.create_ride(
  p_service_kind    text,
  p_pickup_lat      double precision,
  p_pickup_lng      double precision,
  p_dropoff_lat     double precision,
  p_dropoff_lng     double precision,
  p_fare_fcfa       integer,
  p_payment_method  text default 'cash',
  p_pickup_address  text default null,
  p_dropoff_address text default null
) returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid    uuid := auth.uid();
  v_pickup geography;
  v_drop   geography;
  v_id     uuid;
  v_p      record;
  v_label  text;
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;
  if p_service_kind not in ('zemidjan', 'tricycle_fret') then
    raise exception 'SERVICE_INVALIDE' using errcode = '22023';
  end if;
  if p_payment_method not in ('cash', 'mtn', 'moov', 'celtiis') then
    raise exception 'PAIEMENT_INVALIDE' using errcode = '22023';
  end if;
  if p_fare_fcfa is null or p_fare_fcfa < 100 or p_fare_fcfa > 500000 then
    raise exception 'TARIF_INVALIDE' using errcode = '22023';
  end if;
  if p_pickup_lat is null or p_pickup_lng is null
     or p_dropoff_lat is null or p_dropoff_lng is null
     or p_pickup_lat not between -90 and 90 or p_dropoff_lat not between -90 and 90
     or p_pickup_lng not between -180 and 180 or p_dropoff_lng not between -180 and 180 then
    raise exception 'POSITION_INVALIDE' using errcode = '22023';
  end if;

  -- Les demandes restées sans conducteur plus de 30 minutes expirent.
  update public.rides
     set status = 'cancelled', cancelled_at = now(),
         cancel_reason = 'Aucun conducteur disponible'
   where client_id = v_uid and status = 'requested'
     and created_at < now() - interval '30 minutes';

  if exists (
    select 1 from public.rides r
     where r.client_id = v_uid
       and r.status in ('requested', 'accepted', 'arrived', 'in_progress')
  ) then
    raise exception 'COURSE_EN_COURS' using errcode = 'P0001';
  end if;

  v_pickup := st_setsrid(st_makepoint(p_pickup_lng,  p_pickup_lat),  4326)::geography;
  v_drop   := st_setsrid(st_makepoint(p_dropoff_lng, p_dropoff_lat), 4326)::geography;

  insert into public.rides
    (client_id, service_kind, pickup, dropoff, pickup_address, dropoff_address,
     distance_m, fare_fcfa, payment_method)
  values
    (v_uid, p_service_kind, v_pickup, v_drop,
     left(nullif(btrim(p_pickup_address), ''), 300),
     left(nullif(btrim(p_dropoff_address), ''), 300),
     round(st_distance(v_pickup, v_drop))::integer, p_fare_fcfa, p_payment_method)
  returning id into v_id;

  v_label := case p_service_kind when 'zemidjan' then 'Zémidjan' else 'Tricycle Fret' end;

  -- Alerte des 20 conducteurs disponibles les plus proches (5 km).
  for v_p in
    select pv.id
      from public.providers pv
      join public.profiles  pf on pf.id = pv.id
     where pv.provider_kind = p_service_kind
       and pv.statut_validation = 'approved'
       and pv.fin_abonnement > now()
       and pv.disponible
       and not pf.is_suspended
       and pv.id <> v_uid
       and pv.location is not null
       and st_dwithin(pv.location, v_pickup, 5000)
       and not exists (
         select 1 from public.wallets w
          where w.provider_id = pv.id and w.blocked)
     order by st_distance(pv.location, v_pickup)
     limit 20
  loop
    perform public.safe_notify(v_p.id, 'ride_requested', 'Nouvelle course',
      v_label || ' · ' || p_fare_fcfa || ' FCFA',
      jsonb_build_object('ride_id', v_id));
  end loop;

  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 6. Droits d'exécution
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
       and p.proname in ('my_rides', 'ride_details', 'update_ride_provider_position',
                         'ride_action', 'create_ride')
  loop
    execute format('revoke all on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;

  for r in
    select p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'ride_build_json'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
end $$;

commit;