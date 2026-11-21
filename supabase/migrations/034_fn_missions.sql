-- =============================================================================
-- 034 — Missions : create, accept/refuse/arrived/start_work/end_work, list, detail
-- Dart : mission_service.dart, provider_mission_screen.dart
-- Dépend de : 016, 019, 032, 035, 039
-- RÈGLE : le client paie le déplacement AVANT que le prestataire accepte.
--         Le prix de la main d'œuvre vient du catalogue (figé).
-- =============================================================================
begin;

set local search_path to public, extensions;

-- Sérialisation JSON
create or replace function public.mission_build_json(
  m        public.missions,
  p_viewer uuid,
  p_admin  boolean
) returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  v_cl public.profiles%rowtype;
  v_pf public.profiles%rowtype;
  v_pv public.providers%rowtype;
  v_reveal boolean := p_admin or m.status in
                ('accepted','arrived','working','completed');
  v_momo jsonb := null;
  v_items jsonb;
begin
  select * into v_cl from public.profiles  where id = m.client_id;
  select * into v_pf from public.profiles  where id = m.provider_id;
  select * into v_pv from public.providers where id = m.provider_id;

  if v_reveal and v_pv.momo_numero is not null and v_pv.momo_operateur is not null then
    v_momo := jsonb_build_object(
      'operateur', v_pv.momo_operateur,
      'numero',    v_pv.momo_numero,
      'titulaire', v_pv.momo_titulaire);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', i.id, 'nom', i.nom, 'prix_fcfa', i.prix_fcfa)
           order by i.created_at), '[]'::jsonb)
    into v_items
    from public.mission_items i where i.mission_id = m.id;

  return jsonb_build_object(
    'id',              m.id,
    'status',          m.status,
    'vehicle_type',    m.vehicle_type,
    'problem',         m.problem,
    'description',     m.description,
    'client_id',       m.client_id,
    'provider_id',     m.provider_id,
    'client_lat',      m.client_lat,
    'client_lng',      m.client_lng,
    'client_address',  m.client_address,
    'provider_lat',    m.provider_lat,
    'provider_lng',    m.provider_lng,
    'provider_pos_at', m.provider_pos_at,
    'distance_km',     m.distance_km,
    'travel_fee_fcfa', m.travel_fee_fcfa,
    'repair_fee_fcfa', m.repair_fee_fcfa,
    'paid_fcfa',       m.paid_fcfa,
    'accepted_at',     m.accepted_at,
    'arrived_at',      m.arrived_at,
    'work_started_at', m.work_started_at,
    'work_ended_at',   m.work_ended_at,
    'created_at',      m.created_at,
    'client_name',     coalesce(nullif(btrim(coalesce(v_cl.first_name,'')||' '||coalesce(v_cl.last_name,'')),''),'Client'),
    'provider_name',   coalesce(nullif(btrim(v_pv.business_name),''),'Prestataire'),
    'client_phone',    case when v_reveal and (p_admin or m.provider_id = p_viewer)
                            then v_cl.phone else null end,
    'provider_phone',  case when v_reveal and (p_admin or m.client_id = p_viewer)
                            then v_pf.phone else null end,
    'provider_momo',   v_momo,
    'reviewed',        m.reviewed,
    'items',           v_items
  );
end;
$$;
revoke all on function public.mission_build_json(public.missions, uuid, boolean)
  from public, anon, authenticated;

-- Création : items viennent du catalogue, prix figés, déplacement calculé
create or replace function public.create_mission(
  p_provider    uuid,
  p_vehicle     text,
  p_items       uuid[],
  p_lat         double precision,
  p_lng         double precision,
  p_description text default null,
  p_address     text default null
) returns uuid
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid     uuid := auth.uid();
  v_pv      public.providers%rowtype;
  v_ids     uuid[];
  v_found   integer;
  v_labor   integer;
  v_travel  integer;
  v_problem text;
  v_km      numeric;
  v_id      uuid;
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;
  if exists (select 1 from public.profiles where id = v_uid and is_suspended) then
    raise exception 'COMPTE_SUSPENDU' using errcode = 'P0001';
  end if;
  if p_provider is null or p_provider = v_uid then
    raise exception 'PRESTATAIRE_INTROUVABLE' using errcode = 'P0002';
  end if;
  if p_vehicle not in ('moto','tricycle','voiture','bus','camion') then
    raise exception 'VEHICULE_INVALIDE' using errcode = '22023';
  end if;
  if p_lat is null or p_lng is null
     or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'POSITION_INCONNUE' using errcode = 'P0001';
  end if;

  select coalesce(array_agg(distinct x), '{}') into v_ids from unnest(p_items) as x;
  if cardinality(v_ids) = 0 or cardinality(v_ids) > 8 then
    raise exception 'PRESTATIONS_OBLIGATOIRES' using errcode = '22023';
  end if;

  select * into v_pv from public.providers
   where id = p_provider and statut_validation = 'approved' and disponible = true;
  if not found then
    raise exception 'PRESTATAIRE_INDISPONIBLE' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.wallets
              where provider_id = p_provider and blocked) then
    raise exception 'WALLET_BLOQUE' using errcode = 'P0001';
  end if;
  if not (p_vehicle = any (v_pv.vehicle_types)) then
    raise exception 'VEHICULE_NON_PRIS_EN_CHARGE' using errcode = 'P0001';
  end if;
  if v_pv.momo_numero is null or v_pv.momo_operateur is null then
    raise exception 'PAIEMENT_MOBILE_INDISPONIBLE' using errcode = 'P0001';
  end if;
  if (select count(*) from public.missions
       where client_id = v_uid
         and status in ('pending','accepted','arrived','working')) >= 3 then
    raise exception 'TROP_DE_DEMANDES' using errcode = 'P0001';
  end if;

  select count(*), coalesce(sum(i.prix_fcfa), 0)
    into v_found, v_labor
    from public.provider_catalog_items i
   where i.id = any (v_ids)
     and i.provider_id = p_provider
     and i.categorie_vehicule = p_vehicle;
  if v_found <> cardinality(v_ids) then
    raise exception 'PRESTATION_INTROUVABLE' using errcode = 'P0002';
  end if;

  v_km := round((public.haversine_km(p_lat, p_lng, v_pv.latitude, v_pv.longitude) * 1.25)::numeric, 2);
  if v_pv.rayon_max_km is not null and v_km > v_pv.rayon_max_km then
    raise exception 'HORS_RAYON' using errcode = 'P0001';
  end if;
  v_travel := greatest(
    (ceil(v_km * coalesce(v_pv.tarif_km_fcfa, 0) / 50.0))::integer * 50,
    coalesce(v_pv.frais_deplacement_min_fcfa, 0));

  select left(string_agg(i.nom, ' + ' order by i.created_at, i.id), 300)
    into v_problem
    from public.provider_catalog_items i where i.id = any (v_ids);
  if char_length(v_problem) < 3 then
    v_problem := 'Prestation ' || v_problem;
  end if;

  insert into public.missions
    (client_id, provider_id, vehicle_type, problem, description,
     client_lat, client_lng, client_address,
     distance_km, travel_fee_fcfa, repair_fee_fcfa, travel_fee_paid, status)
  values
    (v_uid, p_provider, p_vehicle, v_problem,
     left(nullif(btrim(p_description), ''), 500),
     p_lat, p_lng, left(nullif(btrim(p_address), ''), 300),
     v_km, v_travel, v_labor, false, 'pending')
  returning id into v_id;

  insert into public.mission_items (mission_id, catalog_item_id, nom, prix_fcfa)
  select v_id, i.id, i.nom, i.prix_fcfa
    from public.provider_catalog_items i where i.id = any (v_ids);

  perform public.log_mission_event(v_id, 'created',
    jsonb_build_object('items', cardinality(v_ids), 'distance_km', v_km,
                       'travel_fee_fcfa', v_travel, 'labor_fcfa', v_labor));
  return v_id;
end;
$$;
revoke all on function public.create_mission(
  uuid, text, uuid[], double precision, double precision, text, text)
  from public, anon;
grant execute on function public.create_mission(
  uuid, text, uuid[], double precision, double precision, text, text)
  to authenticated;

-- Log helper (utilisé par tous les RPC ci-dessous)
create or replace function public.log_mission_event(
  p_mission uuid, p_kind text, p_payload jsonb default '{}'::jsonb
) returns void language sql security definer set search_path = public
as $$
  insert into public.mission_events (mission_id, actor_id, kind, payload)
  values (p_mission, auth.uid(), p_kind, coalesce(p_payload, '{}'::jsonb));
$$;
revoke all on function public.log_mission_event(uuid, text, jsonb)
  from public, anon, authenticated;

-- Actions prestataire
create or replace function public.mission_provider_action(
  p_mission uuid, p_action text
) returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid  uuid := auth.uid();
  m      public.missions%rowtype;
  v_dist double precision;
  v_pay_id uuid;
  v_travel_paid boolean;
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;

  select * into m from public.missions
   where id = p_mission and provider_id = v_uid for update;
  if not found then raise exception 'INTROUVABLE' using errcode = 'P0002'; end if;

  if p_action = 'accept' then
    if m.status <> 'pending' then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;
    if not exists (select 1 from public.providers
                    where id = v_uid and statut_validation = 'approved') then
      raise exception 'PRESTATAIRE_NON_VALIDE' using errcode = 'P0001';
    end if;

    select exists (
      select 1 from public.mission_payments pay
       where pay.mission_id = m.id
         and pay.kind = 'trajet'
         and pay.operateur <> 'especes'
         and pay.rejected_at is null
    ) into v_travel_paid;
    if m.travel_fee_fcfa > 0 and not v_travel_paid then
      raise exception 'FRAIS_NON_PAYES' using errcode = 'P0001';
    end if;

    update public.mission_payments
       set confirmed_at = now()
     where mission_id = m.id and kind = 'trajet'
       and confirmed_at is null and rejected_at is null
    returning id into v_pay_id;

    if v_pay_id is not null then
      perform public.apply_travel_commission(m.id, m.travel_fee_fcfa, v_pay_id);
    end if;

    update public.missions
       set status = 'accepted', accepted_at = now(), travel_fee_paid = true
     where id = m.id;
    update public.providers set statut_mission = 'accepted' where id = v_uid;

    perform public.log_mission_event(m.id, 'accepted',
      jsonb_build_object('travel_fee_fcfa', m.travel_fee_fcfa));
    perform public.safe_notify(m.client_id, 'mission_accepted',
      'Dépanneur en route',
      'Votre déplacement est payé. Le dépanneur arrive.',
      jsonb_build_object('mission_id', m.id));

  elsif p_action = 'refuse' then
    if m.status <> 'pending' then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;
    update public.missions set status = 'refused' where id = m.id;
    update public.providers set statut_mission = 'refused' where id = v_uid;
    if m.travel_fee_fcfa > 0 and exists (
      select 1 from public.mission_payments
       where mission_id = m.id and kind = 'trajet'
         and rejected_at is null
    ) then
      perform public.safe_notify_admins(
        'refund_due', 'Remboursement à effectuer',
        'Mission refusée après paiement du déplacement (' || m.travel_fee_fcfa || ' FCFA)',
        jsonb_build_object('mission_id', m.id, 'client_id', m.client_id));
    end if;
    perform public.log_mission_event(m.id, 'refused');
    perform public.safe_notify(m.client_id, 'mission_refused',
      'Demande refusée', 'Ce dépanneur ne peut pas intervenir.',
      jsonb_build_object('mission_id', m.id));

  elsif p_action = 'arrived' then
    if m.status <> 'accepted' then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;
    if m.provider_lat is null or m.provider_lng is null
       or m.provider_pos_at is null
       or m.provider_pos_at < now() - interval '5 minutes' then
      raise exception 'POSITION_INCONNUE' using errcode = 'P0001';
    end if;
    v_dist := public.haversine_km(m.provider_lat, m.provider_lng,
                                  m.client_lat, m.client_lng) * 1000;
    if v_dist > 500 then
      raise exception 'TROP_LOIN' using errcode = 'P0001';
    end if;
    update public.missions set status = 'arrived', arrived_at = now() where id = m.id;
    perform public.log_mission_event(m.id, 'arrived');
    perform public.safe_notify(m.client_id, 'mission_arrived',
      'Dépanneur arrivé', 'Votre dépanneur est sur place.',
      jsonb_build_object('mission_id', m.id));

  elsif p_action = 'start_work' then
    if m.status <> 'arrived' then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;
    update public.missions set status = 'working', work_started_at = now() where id = m.id;
    perform public.log_mission_event(m.id, 'work_started');
    perform public.safe_notify(m.client_id, 'mission_working',
      'Réparation commencée', 'Le dépanneur a commencé le travail.',
      jsonb_build_object('mission_id', m.id));

  elsif p_action = 'end_work' then
    if m.status <> 'working' then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;
    update public.missions set status = 'completed', work_ended_at = now() where id = m.id;
    update public.providers
       set missions_completees = missions_completees + 1, statut_mission = 'completed'
     where id = v_uid;
    perform public.log_mission_event(m.id, 'work_ended',
      jsonb_build_object('labor_fcfa', m.repair_fee_fcfa));
    perform public.safe_notify(m.client_id, 'mission_completed',
      'Réparation terminée',
      'Main d''œuvre : ' || m.repair_fee_fcfa || ' FCFA. Réglez votre dépanneur.',
      jsonb_build_object('mission_id', m.id));

  else
    raise exception 'ACTION_INVALIDE' using errcode = '22023';
  end if;
end;
$$;
revoke all on function public.mission_provider_action(uuid, text) from public, anon;
grant execute on function public.mission_provider_action(uuid, text) to authenticated;

-- Liste des missions
create or replace function public.my_missions()
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  m     public.missions%rowtype;
  v_out jsonb := '[]'::jsonb;
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  for m in
    select * from public.missions
     where client_id = v_uid or provider_id = v_uid
     order by created_at desc limit 100
  loop
    v_out := v_out || jsonb_build_array(public.mission_build_json(m, v_uid, false));
  end loop;
  return v_out;
end;
$$;
revoke all on function public.my_missions() from public, anon;
grant execute on function public.my_missions() to authenticated;

-- Détail
create or replace function public.mission_to_json(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  v_uid   uuid := auth.uid();
  v_admin boolean := public.is_admin();
  m       public.missions%rowtype;
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  select * into m from public.missions where id = p_id;
  if not found or not (v_admin or m.client_id = v_uid or m.provider_id = v_uid) then
    raise exception 'INTROUVABLE' using errcode = 'P0002';
  end if;
  return public.mission_build_json(m, v_uid, v_admin);
end;
$$;
revoke all on function public.mission_to_json(uuid) from public, anon;
grant execute on function public.mission_to_json(uuid) to authenticated;

-- GPS prestataire
create or replace function public.update_provider_position(
  p_mission uuid, p_lat double precision, p_lng double precision
) returns text
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  m     public.missions%rowtype;
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  if p_lat is null or p_lng is null
     or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'POSITION_INVALIDE' using errcode = '22023';
  end if;
  select * into m from public.missions
   where id = p_mission and provider_id = v_uid for update;
  if not found then raise exception 'INTROUVABLE' using errcode = 'P0002'; end if;
  if m.status not in ('accepted','arrived','working') then return m.status; end if;
  update public.missions
     set provider_lat = p_lat, provider_lng = p_lng, provider_pos_at = now()
   where id = m.id;
  return m.status;
end;
$$;
revoke all on function public.update_provider_position(uuid, double precision, double precision)
  from public, anon;
grant execute on function public.update_provider_position(uuid, double precision, double precision)
  to authenticated;

-- Annulation (client ou prestataire)
create or replace function public.cancel_mission(
  p_mission uuid, p_reason text default null
) returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid    uuid := auth.uid();
  m        public.missions%rowtype;
  v_reason text := left(nullif(btrim(p_reason), ''), 300);
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  select * into m from public.missions where id = p_mission for update;
  if not found or not (m.client_id = v_uid or m.provider_id = v_uid) then
    raise exception 'INTROUVABLE' using errcode = 'P0002';
  end if;
  if m.status in ('completed','cancelled','refused') then
    raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
  end if;
  update public.missions
     set status = 'cancelled', cancelled_at = now(),
         cancel_reason = coalesce(v_reason,
           case when v_uid = m.client_id then 'Annulée par le client'
                else 'Annulée par le prestataire' end)
   where id = m.id;
  perform public.log_mission_event(m.id, 'cancelled');
  if v_uid = m.client_id then
    perform public.safe_notify(m.provider_id, 'mission_cancelled',
      'Demande annulée', 'Le client a annulé la demande.',
      jsonb_build_object('mission_id', m.id));
  else
    perform public.safe_notify(m.client_id, 'mission_cancelled',
      'Intervention annulée', 'Le prestataire a annulé l''intervention.',
      jsonb_build_object('mission_id', m.id));
  end if;
end;
$$;
revoke all on function public.cancel_mission(uuid, text) from public, anon;
grant execute on function public.cancel_mission(uuid, text) to authenticated;

commit;