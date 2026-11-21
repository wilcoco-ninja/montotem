-- =============================================================================
-- MONTOTEM : Consolidation Tour de Contrôle, Abonnements & Frais de Déplacement
-- =============================================================================
begin;

-- 1. S'assurer que les tables de missions et abonnements possèdent les bons champs
alter table public.missions
  add column if not exists travel_fee_paid boolean not null default false,
  add column if not exists prank_reported  boolean not null default false;

-- 2. Fonction de création de mission avec exigence de paiement des frais de déplacement
create or replace function public.create_mission(
  p_provider uuid, p_vehicle text, p_problem text, p_description text,
  p_lat double precision, p_lng double precision, p_address text default null
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_pv   public.providers%rowtype;
  v_km   numeric;
  v_fee  integer;
  v_id   uuid;
  v_name text;
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  if p_provider = v_uid then raise exception 'PRESTATAIRE_INTROUVABLE' using errcode = 'P0002'; end if;
  
  -- Vérifier l'abonnement actif du prestataire (style Canal+)
  select * into v_pv from public.providers pv
   where pv.id = p_provider and pv.statut_validation = 'approved' and pv.fin_abonnement > now();
  if not found then raise exception 'PRESTATAIRE_INTROUVABLE' using errcode = 'P0002'; end if;

  v_km  := round((public.haversine_km(p_lat, p_lng, v_pv.latitude, v_pv.longitude) * 1.25)::numeric, 2);
  v_fee := greatest((ceil(v_km * v_pv.tarif_km_fcfa / 50.0))::integer * 50, v_pv.frais_deplacement_min_fcfa);

  insert into public.missions
    (client_id, provider_id, vehicle_type, problem, description, client_lat, client_lng,
     client_address, distance_km, travel_fee_fcfa, travel_fee_paid, status)
  values
    (v_uid, p_provider, p_vehicle, btrim(p_problem), left(nullif(btrim(p_description), ''), 500),
     p_lat, p_lng, left(nullif(btrim(p_address), ''), 300), v_km, v_fee, false, 'pending')
  returning id into v_id;

  select coalesce(nullif(btrim(coalesce(c.first_name, '') || ' ' || coalesce(c.last_name, '')), ''), 'Un client')
    into v_name from public.profiles c where c.id = v_uid;

  perform public.log_mission_event(v_id, 'created',
    jsonb_build_object('problem', btrim(p_problem), 'distance_km', v_km, 'travel_fee_fcfa', v_fee));
    
  return v_id;
end;
$$;

-- 3. Validation du paiement des frais de déplacement (déclenche le départ du prestataire)
create or replace function public.pay_mission_travel_fee(p_mission uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_m   public.missions%rowtype;
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  select * into v_m from public.missions mi where mi.id = p_mission and mi.client_id = v_uid for update;
  if not found then raise exception 'INTROUVABLE' using errcode = 'P0002'; end if;

  update public.missions set travel_fee_paid = true, paid_fcfa = paid_fcfa + travel_fee_fcfa where id = v_m.id;
  
  perform public.log_mission_event(v_m.id, 'travel_fee_paid', jsonb_build_object('amount', v_m.travel_fee_fcfa));
  perform public.notify_user(v_m.provider_id, 'mission_travel_paid', 'Déplacement payé',
    'Frais de déplacement réglés. Vous pouvez démarrer vers le client.', jsonb_build_object('mission_id', v_m.id));
end;
$$;

-- 4. Gestion du signalement de canulard (dédommagement par acquisition des frais de déplacement)
create or replace function public.report_mission_prank(p_mission uuid, p_details text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_m   public.missions%rowtype;
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  select * into v_m from public.missions mi where mi.id = p_mission and mi.provider_id = v_uid for update;
  if not found then raise exception 'INTROUVABLE' using errcode = 'P0002'; end if;

  update public.missions
     set status = 'cancelled', prank_reported = true, cancel_reason = 'Canulard / Client absent'
   where id = v_m.id;

  -- Enregistrement du signalement client pour la tour de contrôle admin
  insert into public.provider_reports (reporter_id, provider_id, mission_id, motif, details, status)
  values (v_uid, v_uid, v_m.id, 'fausse_arrivee', coalesce(p_details, 'Client injoignable ou canulard sur les lieux'), 'open');

  perform public.notify_admins('prank_reported', 'Canulard signalé',
    'Mission annulée pour canulard. Frais de déplacement acquis au prestataire.', jsonb_build_object('mission_id', v_m.id));
end;
$$;

commit;