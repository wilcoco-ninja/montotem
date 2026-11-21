-- =============================================================================
-- 037 — Courses : create, actions, detail, list (3 service_kind)
-- Dart : ride_service.dart, ride_request_screen.dart, ride_tracking_screen.dart
-- Dépend de : 017, 019, 039
-- =============================================================================
begin;

set local search_path to public, extensions;

-- Sérialisation
create or replace function public.ride_build_json(
  r public.rides, p_viewer uuid, p_admin boolean
) returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  v_reveal boolean := p_admin or r.status in
                ('accepted','arrived','in_progress','completed');
  v_cl public.profiles%rowtype;
  v_pf public.profiles%rowtype;
  v_pv public.providers%rowtype;
  v_momo jsonb := null;
begin
  select * into v_cl from public.profiles where id = r.client_id;
  select * into v_pf from public.profiles where id = r.provider_id;
  select * into v_pv from public.providers where id = r.provider_id;

  if v_reveal and r.payment_method <> 'cash'
     and v_pv.momo_numero is not null
     and v_pv.momo_operateur = r.payment_method
     and (p_admin or p_viewer = r.client_id) then
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
    'commission_fcfa', case when p_admin or p_viewer = r.provider_id
                            then r.commission_fcfa else null end,
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
    'client_name',     coalesce(nullif(btrim(coalesce(v_cl.first_name,'')||' '||coalesce(v_cl.last_name,'')),''),'Client'),
    'provider_name',   case when r.provider_id is null then null
                            else coalesce(nullif(btrim(v_pv.business_name),''),'Conducteur') end,
    'client_phone',    case when v_reveal and (p_admin or p_viewer = r.provider_id)
                            then v_cl.phone else null end,
    'provider_phone',  case when v_reveal and (p_admin or p_viewer = r.client_id)
                            then v_pf.phone else null end,
    'provider_momo',   v_momo
  );
end;
$$;
revoke all on function public.ride_build_json(public.rides, uuid, boolean)
  from public, anon, authenticated;

-- Création
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
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid    uuid := auth.uid();
  v_pickup geography;
  v_drop   geography;
  v_id     uuid;
  v_p      record;
  v_label  text;
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  if p_service_kind not in ('zemidjan','tricycle_passenger','tricycle_fret') then
    raise exception 'SERVICE_INVALIDE' using errcode = '22023';
  end if;
  if p_payment_method not in ('cash','mtn','moov','celtiis') then
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

  update public.rides
     set status = 'cancelled', cancelled_at = now(),
         cancel_reason = 'Aucun conducteur disponible'
   where client_id = v_uid and status = 'requested'
     and created_at < now() - interval '30 minutes';

  if exists (select 1 from public.rides
              where client_id = v_uid
                and status in ('requested','accepted','arrived','in_progress')) then
    raise exception 'COURSE_EN_COURS' using errcode = 'P0001';
  end if;

  v_pickup := st_setsrid(st_makepoint(p_pickup_lng, p_pickup_lat), 4326)::geography;
  v_drop   := st_setsrid(st_makepoint(p_dropoff_lng, p_dropoff_lat), 4326)::geography;

  insert into public.rides
    (client_id, service_kind, pickup, dropoff, pickup_address, dropoff_address,
     distance_m, fare_fcfa, payment_method)
  values
    (v_uid, p_service_kind, v_pickup, v_drop,
     left(nullif(btrim(p_pickup_address),''),300),
     left(nullif(btrim(p_dropoff_address),''),300),
     round(st_distance(v_pickup, v_drop))::integer,
     p_fare_fcfa, p_payment_method)
  returning id into v_id;

  v_label := case p_service_kind
    when 'zemidjan' then 'Zémidjan'
    when 'tricycle_passenger' then 'Kloboto Passager'
    when 'tricycle_fret' then 'Kloboto Colis'
  end;

  for v_p in
    select pv.id from public.providers pv
      join public.profiles pf on pf.id = pv.id
     where pv.provider_kind = p_service_kind
       and pv.statut_validation = 'approved'
       and pv.disponible = true
       and not pf.is_suspended
       and pv.id <> v_uid
       and pv.location is not null
       and st_dwithin(pv.location, v_pickup, 5000)
       and not exists (select 1 from public.wallets w
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
revoke all on function public.create_ride(text, double precision, double precision, double precision, double precision, integer, text, text, text)
  from public, anon;
grant execute on function public.create_ride(text, double precision, double precision, double precision, double precision, integer, text, text, text)
  to authenticated;

-- Actions
create or replace function public.ride_action(
  p_ride uuid, p_action text, p_fare integer default null, p_reason text default null
) returns text
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid   uuid := auth.uid();
  v_r     public.rides%rowtype;
  v_pv    public.providers%rowtype;
  v_final integer;
  v_other uuid;
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  select * into v_r from public.rides where id = p_ride for update;
  if not found then raise exception 'INTROUVABLE' using errcode = 'P0002'; end if;

  if p_action = 'accept' then
    if v_r.status <> 'requested' or v_r.provider_id is not null then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;
    if v_r.client_id = v_uid then
      raise exception 'INTERDIT' using errcode = '42501';
    end if;
    select * into v_pv from public.providers
     where id = v_uid and statut_validation = 'approved';
    if not found then
      raise exception 'PRESTATAIRE_NON_ACTIF' using errcode = 'P0001';
    end if;
    if v_pv.provider_kind <> v_r.service_kind then
      raise exception 'SERVICE_INCOMPATIBLE' using errcode = 'P0001';
    end if;
    if v_r.payment_method <> 'cash'
       and (v_pv.momo_numero is null
            or v_pv.momo_operateur is distinct from v_r.payment_method) then
      raise exception 'MOMO_NON_CONFIGURE' using errcode = 'P0001';
    end if;
    update public.rides
       set provider_id = v_uid, status = 'accepted', accepted_at = now()
     where id = v_r.id;
    perform public.safe_notify(v_r.client_id, 'ride_accepted',
      'Conducteur en route', 'Votre course est acceptée.',
      jsonb_build_object('ride_id', v_r.id));
    return 'accepted';

  elsif p_action in ('arrived','start','complete') then
    if v_r.provider_id is distinct from v_uid then
      raise exception 'INTERDIT' using errcode = '42501';
    end if;

    if p_action = 'arrived' then
      if v_r.status <> 'accepted' then
        raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
      end if;
      update public.rides set status = 'arrived', arrived_at = now() where id = v_r.id;
      perform public.safe_notify(v_r.client_id, 'ride_arrived',
        'Conducteur arrivé', 'Votre conducteur est sur place.',
        jsonb_build_object('ride_id', v_r.id));
      return 'arrived';

    elsif p_action = 'start' then
      if v_r.status <> 'arrived' then
        raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
      end if;
      update public.rides set status = 'in_progress', started_at = now() where id = v_r.id;
      perform public.safe_notify(v_r.client_id, 'ride_started',
        'Course démarrée', 'Bonne route !',
        jsonb_build_object('ride_id', v_r.id));
      return 'in_progress';

    else
      if v_r.status <> 'in_progress' then
        raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
      end if;
      v_final := coalesce(p_fare, v_r.fare_fcfa);
      if v_final < 100 or v_final > 500000 or v_final > (v_r.fare_fcfa * 3 / 2) then
        raise exception 'TARIF_INVALIDE' using errcode = '22023';
      end if;
      update public.rides
         set status = 'completed', final_fare_fcfa = v_final
       where id = v_r.id;
      perform public.safe_notify(v_r.client_id, 'ride_completed',
        'Course terminée', 'Montant : ' || v_final || ' FCFA.',
        jsonb_build_object('ride_id', v_r.id));
      return 'completed';
    end if;

  elsif p_action = 'cancel' then
    if v_uid not in (v_r.client_id, coalesce(v_r.provider_id, v_r.client_id)) then
      raise exception 'INTERDIT' using errcode = '42501';
    end if;
    if v_r.status in ('completed','cancelled','in_progress') then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;
    update public.rides
       set status = 'cancelled', cancelled_at = now(), cancelled_by = v_uid,
           cancel_reason = left(nullif(btrim(p_reason),''),300)
     where id = v_r.id;
    v_other := case when v_uid = v_r.client_id then v_r.provider_id else v_r.client_id end;
    if v_other is not null then
      perform public.safe_notify(v_other, 'ride_cancelled',
        'Course annulée', 'La course a été annulée.',
        jsonb_build_object('ride_id', v_r.id));
    end if;
    return 'cancelled';
  end if;
  raise exception 'ACTION_INVALIDE' using errcode = '22023';
end;
$$;
revoke all on function public.ride_action(uuid, text, integer, text) from public, anon;
grant execute on function public.ride_action(uuid, text, integer, text) to authenticated;

-- Détail
create or replace function public.ride_details(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_admin boolean := public.is_admin();
  r public.rides%rowtype;
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  select * into r from public.rides where id = p_id;
  if not found or not (v_admin or r.client_id = v_uid or r.provider_id = v_uid) then
    raise exception 'INTROUVABLE' using errcode = 'P0002';
  end if;
  return public.ride_build_json(r, v_uid, v_admin);
end;
$$;
revoke all on function public.ride_details(uuid) from public, anon;
grant execute on function public.ride_details(uuid) to authenticated;

-- Historique
create or replace function public.my_rides()
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  r     public.rides%rowtype;
  v_out jsonb := '[]'::jsonb;
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  for r in
    select * from public.rides
     where client_id = v_uid or provider_id = v_uid
     order by created_at desc limit 100
  loop
    v_out := v_out || jsonb_build_array(public.ride_build_json(r, v_uid, false));
  end loop;
  return v_out;
end;
$$;
revoke all on function public.my_rides() from public, anon;
grant execute on function public.my_rides() to authenticated;

commit;