-- ============================================================================
-- MonTotem — F-25 : FONCTIONS MISSIONS (réparation « Mes demandes »)
-- ============================================================================
-- Symptôme : l'écran client « Mes demandes de dépannage » affiche
-- « Opération impossible. Réessayez. » car le RPC my_missions (et ses
-- compagnons de la migration 034) est absent de la base : Postgrest répond
-- PGRST202 « Could not find the function », mappé sur le message par défaut.
--
-- Ce script recrée TOUTES les fonctions de la migration 034, de façon
-- idempotente (create or replace) :
--   mission_build_json, create_mission, log_mission_event,
--   mission_provider_action, my_missions, mission_to_json,
--   update_provider_position, cancel_mission.
--
-- Prérequis (déjà en base) : tables missions/mission_items/mission_events/
-- mission_payments, wallets, haversine_km, is_admin(), app_config.
-- ============================================================================

begin;

set local search_path to public, extensions;

-- NOTE : create_mission n'est PAS recréé ici — F-20 contient déjà une
-- version plus récente (frais de déplacement atelier). On ne régresse pas.

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