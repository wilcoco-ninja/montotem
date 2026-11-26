-- ============================================================================
-- F-20 · Déplacement des prestataires piloté par l'admin (par type d'atelier)
--
-- À exécuter UNE FOIS dans Supabase SQL Editor
-- (titre conseillé : « F-20 Deplacement par atelier »).
--
-- Règles de la plateforme (confirmées) :
--   - Le client paie TOUJOURS le déplacement (Mobile Money) AVANT que le
--     prestataire n'accepte la mission ;
--   - Le prestataire fixe lui-même le prix de chaque travail dans son
--     catalogue (provider_catalog_items.prix_fcfa) ;
--   - À « Travail terminé », le client paie le total : déplacement (déjà
--     réglé) + main d'œuvre, en cash ou Mobile Money ; la commission
--     plateforme est prélevée ensuite (apply_travel_commission /
--     commission cash).
--
-- Nouveautés de ce script :
--   1. Le tarif / km du déplacement N'EST PLUS fixé librement par chaque
--      prestataire : il dépend du type d'atelier et est modifiable par
--      l'ADMIN dans l'écran « Tarifs & prix » :
--        atelier / mécanicien ambulant  → deplacement_atelier_fcfa_km (100)
--        service garage                 → deplacement_garage_fcfa_km  (150)
--        station essence / carburant    → deplacement_station_fcfa_km (100)
--        remorquage (dépanneuse)        → sos_remorquage_fcfa_km      (400, F-19)
--   2. create_mission applique ce tarif officiel selon provider_kind.
--   3. provider_public_catalog renvoie tarif_km_admin pour que l'estimation
--      affichée au client soit exactement celle que le serveur appliquera.
--
-- Prérequis : F-19 (clés ride_/sos_), 031, 034. Non destructif, idempotent.
-- ============================================================================

begin;

set local search_path = public, extensions;

-- ----------------------------------------------------------------------------
-- 1. Tarifs officiels de déplacement par type d'atelier (éditables par l'admin)
-- ----------------------------------------------------------------------------
insert into public.app_config (key, value_int, note) values
  ('deplacement_atelier_fcfa_km',  100, 'Deplacement atelier / technicien ambulant — FCFA/km'),
  ('deplacement_garage_fcfa_km',   150, 'Deplacement service garage — FCFA/km'),
  ('deplacement_station_fcfa_km',  100, 'Deplacement station essence / carburant — FCFA/km')
on conflict (key) do update
  set value_int  = excluded.value_int,
      note       = excluded.note,
      updated_at = now();

-- ----------------------------------------------------------------------------
-- 2. create_mission : tarif de déplacement officiel selon le type d'atelier
-- ----------------------------------------------------------------------------
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
  v_uid      uuid := auth.uid();
  v_pv       public.providers%rowtype;
  v_ids      uuid[];
  v_found    integer;
  v_labor    integer;
  v_travel   integer;
  v_problem  text;
  v_km       numeric;
  v_id       uuid;
  v_key      text;
  v_tarif_km integer;
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

  -- Tarif de déplacement officiel (admin) selon le type d'atelier.
  v_key := case v_pv.provider_kind
    when 'garage'     then 'deplacement_garage_fcfa_km'
    when 'station'    then 'deplacement_station_fcfa_km'
    when 'remorquage' then 'sos_remorquage_fcfa_km'
    else 'deplacement_atelier_fcfa_km'
  end;
  select value_int into v_tarif_km from public.app_config where key = v_key;
  -- Repli : le tarif du prestataire, puis 100 FCFA/km.
  v_tarif_km := coalesce(v_tarif_km, v_pv.tarif_km_fcfa, 100);

  v_km := round((public.haversine_km(p_lat, p_lng, v_pv.latitude, v_pv.longitude) * 1.25)::numeric, 2);
  if v_pv.rayon_max_km is not null and v_km > v_pv.rayon_max_km then
    raise exception 'HORS_RAYON' using errcode = 'P0001';
  end if;
  v_travel := greatest(
    (ceil(v_km * coalesce(v_tarif_km, 0) / 50.0))::integer * 50,
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
                       'travel_fee_fcfa', v_travel, 'labor_fcfa', v_labor,
                       'tarif_km_officiel', v_tarif_km));
  return v_id;
end;
$$;
revoke all on function public.create_mission(
  uuid, text, uuid[], double precision, double precision, text, text)
  from public, anon;
grant execute on function public.create_mission(
  uuid, text, uuid[], double precision, double precision, text, text)
  to authenticated;

-- ----------------------------------------------------------------------------
-- 3. provider_public_catalog : renvoyer aussi le tarif admin (affichage client)
-- ----------------------------------------------------------------------------
create or replace function public.provider_public_catalog(p_provider uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  v_pv public.providers%rowtype;
begin
  select pv.* into v_pv
    from public.providers pv
    join public.profiles  pf on pf.id = pv.id
   where pv.id = p_provider
     and pv.statut_validation = 'approved'
     and not pf.is_suspended;
  if not found then return null; end if;

  return jsonb_build_object(
    'vehicle_types', to_jsonb(v_pv.vehicle_types),
    'skills', coalesce((
        select jsonb_agg(s.label order by s.created_at)
          from public.provider_skills s where s.provider_id = p_provider
      ), '[]'::jsonb),
    'tarif_km_fcfa', v_pv.tarif_km_fcfa,
    'tarif_km_admin', (
      select value_int from public.app_config where key =
        case v_pv.provider_kind
          when 'garage'     then 'deplacement_garage_fcfa_km'
          when 'station'    then 'deplacement_station_fcfa_km'
          when 'remorquage' then 'sos_remorquage_fcfa_km'
          else 'deplacement_atelier_fcfa_km'
        end),
    'frais_deplacement_min_fcfa', v_pv.frais_deplacement_min_fcfa,
    'rayon_max_km', v_pv.rayon_max_km,
    'accepte_mobile_money', (v_pv.momo_numero is not null and v_pv.momo_operateur is not null),
    'services', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', i.id,
          'nom', i.nom,
          'categorie_vehicule', i.categorie_vehicule,
          'prix_fcfa', i.prix_fcfa)
          order by i.categorie_vehicule, i.created_at, i.id)
          from public.provider_catalog_items i where i.provider_id = p_provider
      ), '[]'::jsonb),
    'id_document_type', v_pv.id_document_type,
    'photo_garage_url', v_pv.photo_garage_url,
    'garage_description', v_pv.garage_description
  );
end;
$$;
revoke all on function public.provider_public_catalog(uuid) from public;
grant execute on function public.provider_public_catalog(uuid) to anon, authenticated;

commit;

-- ── Contrôles (à exécuter après le script) ──
-- SELECT key, value_int FROM public.app_config
--  WHERE key LIKE 'deplacement_%' ORDER BY key;
-- attendu : atelier 100, garage 150, station 100 (+ express 100, remorquage 400 de F-19).
