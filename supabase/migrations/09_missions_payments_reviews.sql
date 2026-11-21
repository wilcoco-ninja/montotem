-- Suppression préalable pour autoriser la mise à jour de la signature/type de retour
drop function if exists public.mission_provider_action(uuid, text, integer);

create or replace function public.mission_provider_action(
  p_mission uuid,
  p_action  text,
  p_amount  integer default null
) returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid  uuid := auth.uid();
  m      public.missions%rowtype;
  v_dist double precision;
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;

  select * into m from public.missions
   where id = p_mission and provider_id = v_uid
   for update;
  if not found then
    raise exception 'INTROUVABLE' using errcode = 'P0002';
  end if;

  if p_action = 'accept' then
    if m.status <> 'pending' then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;
    if not exists (
      select 1 from public.providers pv
       where pv.id = v_uid and pv.statut_validation = 'approved'
    ) then
      raise exception 'PRESTATAIRE_NON_VALIDE' using errcode = 'P0001';
    end if;

    update public.missions set status = 'accepted', accepted_at = now() where id = m.id;
    update public.providers set statut_mission = 'accepted' where id = v_uid;
    perform public.log_mission_event(m.id, 'accepted');
    perform public.safe_notify(m.client_id, 'mission_accepted', 'Dépanneur en route',
      'Votre demande a été acceptée. Suivez son arrivée en direct.',
      jsonb_build_object('mission_id', m.id));

  elsif p_action = 'refuse' then
    if m.status <> 'pending' then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;
    update public.missions set status = 'refused' where id = m.id;
    update public.providers set statut_mission = 'refused' where id = v_uid;
    perform public.log_mission_event(m.id, 'refused');
    perform public.safe_notify(m.client_id, 'mission_refused', 'Demande refusée',
      'Ce dépanneur ne peut pas intervenir. Choisissez-en un autre sur la carte.',
      jsonb_build_object('mission_id', m.id));

  elsif p_action = 'arrived' then
    if m.status <> 'accepted' then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;
    if m.provider_lat is null or m.provider_lng is null
       or m.provider_pos_at is null or m.provider_pos_at < now() - interval '5 minutes' then
      raise exception 'POSITION_INCONNUE' using errcode = 'P0001';
    end if;
    v_dist := public.haversine_km(m.provider_lat, m.provider_lng, m.client_lat, m.client_lng) * 1000;
    if v_dist > 500 then
      raise exception 'TROP_LOIN' using errcode = 'P0001';
    end if;
    update public.missions set status = 'arrived', arrived_at = now() where id = m.id;
    perform public.log_mission_event(m.id, 'arrived');
    perform public.safe_notify(m.client_id, 'mission_arrived', 'Dépanneur arrivé',
      'Votre dépanneur est sur place.', jsonb_build_object('mission_id', m.id));

  elsif p_action = 'start_work' then
    if m.status <> 'arrived' then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;
    update public.missions set status = 'working', work_started_at = now() where id = m.id;
    perform public.log_mission_event(m.id, 'work_started');
    perform public.safe_notify(m.client_id, 'mission_working', 'Réparation commencée',
      'Le dépanneur a commencé le travail.', jsonb_build_object('mission_id', m.id));

  elsif p_action = 'end_work' then
    if m.status <> 'working' then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;
    if p_amount is null or p_amount < 0 or p_amount > 10000000 then
      raise exception 'MONTANT_INVALIDE' using errcode = '22023';
    end if;
    update public.missions
       set status = 'completed', work_ended_at = now(), repair_fee_fcfa = p_amount
     where id = m.id;
    update public.providers
       set missions_completees = missions_completees + 1, statut_mission = 'completed'
     where id = v_uid;
    perform public.log_mission_event(m.id, 'work_ended', jsonb_build_object('repair_fee_fcfa', p_amount));
    perform public.safe_notify(m.client_id, 'mission_completed', 'Réparation terminée',
      'Consultez le montant et réglez votre dépanneur.',
      jsonb_build_object('mission_id', m.id));

  else
    raise exception 'ACTION_INVALIDE' using errcode = '22023';
  end if;
end;
$$;