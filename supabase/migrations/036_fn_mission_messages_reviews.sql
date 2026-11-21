begin;

set local search_path to public, extensions;

-- 1. Nettoyage préalable pour éviter les conflits de types de retour
drop function if exists public.send_mission_message(uuid, text);
drop function if exists public.submit_review(uuid, integer, text);
drop function if exists public.submit_provider_report(uuid, uuid, text, text);

-- 2. Chat
create or replace function public.send_mission_message(
  p_mission uuid, p_body text
) returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid  uuid := auth.uid();
  m      public.missions%rowtype;
  v_body text := left(btrim(coalesce(p_body, '')), 500);
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  if char_length(v_body) < 1 then
    raise exception 'MESSAGE_VIDE' using errcode = '22023';
  end if;
  select * into m from public.missions where id = p_mission;
  if not found or not (m.client_id = v_uid or m.provider_id = v_uid) then
    raise exception 'INTROUVABLE' using errcode = 'P0002';
  end if;
  if m.status in ('completed','cancelled','refused') then
    raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
  end if;
  insert into public.mission_messages (mission_id, sender_id, body)
  values (m.id, v_uid, v_body);
end;
$$;
revoke all on function public.send_mission_message(uuid, text) from public, anon;
grant execute on function public.send_mission_message(uuid, text) to authenticated;

-- 3. Avis
create or replace function public.submit_review(
  p_mission uuid, p_stars integer, p_comment text default null
) returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid    uuid := auth.uid();
  m        public.missions%rowtype;
  v_pts    integer := 10;
  v_total  integer;
  v_notes  integer;
  v_note   numeric(3,2);
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  if p_stars is null or p_stars not between 1 and 5 then
    raise exception 'NOTE_INVALIDE' using errcode = '22023';
  end if;
  select * into m from public.missions where id = p_mission for update;
  if not found or m.client_id <> v_uid then
    raise exception 'INTROUVABLE' using errcode = 'P0002';
  end if;
  if m.status <> 'completed' then
    raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.mission_reviews where mission_id = m.id) then
    raise exception 'AVIS_DEJA_DONNE' using errcode = 'P0001';
  end if;
  if p_comment is not null and char_length(btrim(p_comment)) >= 20 then
    v_pts := v_pts + 5;
  end if;
  insert into public.mission_reviews (mission_id, client_id, provider_id, stars, comment)
  values (m.id, v_uid, m.provider_id, p_stars,
          left(nullif(btrim(p_comment), ''), 500));
  insert into public.star_points_ledger (client_id, mission_id, delta, reason)
  values (v_uid, m.id, v_pts,
          case when v_pts > 10 then 'avis_detaille' else 'avis' end);
  update public.profiles set star_points = star_points + v_pts
   where id = v_uid returning star_points into v_total;
  update public.missions set reviewed = true where id = m.id;
  select count(*), avg(stars) into v_notes, v_note
    from public.mission_reviews where provider_id = m.provider_id;
  if v_notes > 0 then
    update public.providers set note_moyenne = round(v_note, 2)
     where id = m.provider_id;
  end if;
  if p_stars >= 4 then
    update public.providers set clients_satisfaits = clients_satisfaits + 1
     where id = m.provider_id;
  elsif p_stars <= 2 then
    update public.providers set clients_insatisfaits = clients_insatisfaits + 1
     where id = m.provider_id;
  end if;
  return jsonb_build_object('points', v_pts, 'total', v_total);
end;
$$;
revoke all on function public.submit_review(uuid, integer, text) from public, anon;
grant execute on function public.submit_review(uuid, integer, text) to authenticated;

-- 4. Signalement
create or replace function public.submit_provider_report(
  p_provider uuid, p_mission uuid default null,
  p_motif text default null, p_details text default null
) returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid   uuid := auth.uid();
  v_motif text := btrim(coalesce(p_motif, ''));
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  if p_provider is null or p_provider = v_uid then
    raise exception 'PRESTATAIRE_INTROUVABLE' using errcode = 'P0002';
  end if;
  if char_length(v_motif) < 3 then
    raise exception 'MOTIF_OBLIGATOIRE' using errcode = '22023';
  end if;
  if p_mission is not null and not exists (
    select 1 from public.missions m
     where m.id = p_mission and m.client_id = v_uid and m.provider_id = p_provider
  ) then
    raise exception 'INTROUVABLE' using errcode = 'P0002';
  end if;
  insert into public.provider_reports
    (reporter_id, provider_id, mission_id, motif, details, status)
  values (v_uid, p_provider, p_mission, v_motif,
          left(nullif(btrim(p_details), ''), 1000), 'open');
  perform public.safe_notify_admins(
    'provider_reported', 'Nouveau signalement', v_motif,
    jsonb_build_object('provider_id', p_provider,
                       'mission_id', p_mission, 'reporter_id', v_uid));
end;
$$;
revoke all on function public.submit_provider_report(uuid, uuid, text, text)
  from public, anon;
grant execute on function public.submit_provider_report(uuid, uuid, text, text)
  to authenticated;

commit;