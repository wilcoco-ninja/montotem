-- ============================================================================
-- F-19 · Tarifs kilométriques officiels, modifiables depuis l'écran admin
--
-- À exécuter UNE FOIS dans Supabase SQL Editor
-- (titre conseillé : « F-19 Tarifs km et prix serveur »).
--
-- Contenu :
--   1. Valeurs officielles des tarifs / km dans app_config
--      (zemidjan 150, cloboto 200, kloboto 300, déplacement express 100,
--       remorquage 400 FCFA/km) — modifiables ensuite par le super_admin
--       depuis l'écran admin « Tarifs & prix ».
--   2. create_ride : le PRIX MINIMUM est recalculé côté serveur
--      (base + tarif_km × distance) — un client ne peut plus payer
--      moins que le tarif officiel pour la distance parcourue.
--   3. sos_match_providers : le déplacement du devis SOS utilise le tarif
--      officiel (express 100 FCFA/km, remorquage 400 FCFA/km) au lieu du
--      tarif libre de chaque prestataire.
--   4. provider_kind_from_metier : reconnaissance des nouveaux métiers
--      (remorquage, lavage, carburant).
--
-- Prérequis : 003, 048 (app_config), 037 (create_ride), sos/07 (match).
-- Non destructif, idempotent.
-- ============================================================================

begin;

set local search_path = public, extensions;

-- ----------------------------------------------------------------------------
-- 1. Tarifs officiels (app_config) — la source unique, éditable côté admin
-- ----------------------------------------------------------------------------
insert into public.app_config (key, value_int, note) values
  ('ride_zemidjan_base_fcfa',         300, 'Zemidjan — prix de depart'),
  ('ride_zemidjan_per_km_fcfa',       150, 'Zemidjan — prix / km'),
  ('ride_cloboto_base_fcfa',          500, 'Cloboto — prix de depart'),
  ('ride_cloboto_per_km_fcfa',        200, 'Cloboto — prix / km'),
  ('ride_kloboto_base_fcfa',          700, 'Kloboto — prix de depart'),
  ('ride_kloboto_per_km_fcfa',        300, 'Kloboto — prix / km'),
  ('sos_deplacement_express_fcfa_km', 100, 'Deplacement prestataire express (vehicule de travail) — FCFA/km'),
  ('sos_remorquage_fcfa_km',          400, 'Remorquage (depanneuse, vehicules bloques) — FCFA/km')
on conflict (key) do update
  set value_int  = excluded.value_int,
      note       = excluded.note,
      updated_at = now();

-- ----------------------------------------------------------------------------
-- 2. create_ride : recalcul serveur du prix minimum
--    Le client envoie toujours son estimation (affichée à l'écran), mais le
--    serveur refuse un prix inférieur à base + tarif_km × distance (ligne
--    droite). Le prix final = max(estimation client, prix minimum serveur).
-- ----------------------------------------------------------------------------
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
  v_uid     uuid := auth.uid();
  v_pickup  geography;
  v_drop    geography;
  v_id      uuid;
  v_p       record;
  v_label   text;
  v_km      numeric;
  v_base    integer;
  v_per_km  integer;
  v_min     integer;
  v_fare    integer;
  v_base_key text;
  v_km_key   text;
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

  -- Prix minimum officiel : base + tarif/km × distance (ligne droite).
  -- Les tarifs vivent dans app_config, modifiables depuis l'écran admin.
  v_km := round(st_distance(v_pickup, v_drop))::numeric / 1000.0;

  v_base_key := case p_service_kind
    when 'zemidjan' then 'ride_zemidjan_base_fcfa'
    when 'tricycle_passenger' then 'ride_cloboto_base_fcfa'
    else 'ride_kloboto_base_fcfa'
  end;
  v_km_key := case p_service_kind
    when 'zemidjan' then 'ride_zemidjan_per_km_fcfa'
    when 'tricycle_passenger' then 'ride_cloboto_per_km_fcfa'
    else 'ride_kloboto_per_km_fcfa'
  end;

  select value_int into v_base   from public.app_config where key = v_base_key;
  select value_int into v_per_km from public.app_config where key = v_km_key;

  v_min  := round(coalesce(v_base, 300)::numeric + coalesce(v_per_km, 150)::numeric * v_km)::integer;
  v_fare := greatest(p_fare_fcfa, v_min, 100);

  insert into public.rides
    (client_id, service_kind, pickup, dropoff, pickup_address, dropoff_address,
     distance_m, fare_fcfa, payment_method)
  values
    (v_uid, p_service_kind, v_pickup, v_drop,
     left(nullif(btrim(p_pickup_address),''),300),
     left(nullif(btrim(p_dropoff_address),''),300),
     round(st_distance(v_pickup, v_drop))::integer,
     v_fare, p_payment_method)
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
      v_label || ' · ' || v_fare || ' FCFA',
      jsonb_build_object('ride_id', v_id));
  end loop;

  return v_id;
end;
$$;
revoke all on function public.create_ride(text, double precision, double precision, double precision, double precision, integer, text, text, text)
  from public, anon;
grant execute on function public.create_ride(text, double precision, double precision, double precision, double precision, integer, text, text, text)
  to authenticated;

-- ----------------------------------------------------------------------------
-- 3. sos_match_providers : déplacement au tarif officiel
--    express = 100 FCFA/km (sos_deplacement_express_fcfa_km),
--    remorquage = 400 FCFA/km (sos_remorquage_fcfa_km) dès que la panne
--    exige une dépanneuse. Le minimum du prestataire reste respecté.
-- ----------------------------------------------------------------------------
create or replace function sos_match_providers(
  p_vehicule text,
  p_panne    text,
  p_lat      double precision,
  p_lng      double precision,
  p_rayon_km numeric default 15,
  p_limit    int    default 5
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $func$
declare
  v_vehicule   text := upper(btrim(p_vehicule));
  v_panne      text := upper(btrim(p_panne));
  v_existe     boolean;
  v_piece_code text;
  v_piece_obl  boolean;
  v_comp       text[];
  v_hab        text[];
  v_services   text[];
  v_remorquage boolean;
  v_tarif_km   integer;
begin
  -- Validation stricte : la panne doit être déclarée compatible avec le véhicule.
  select true into v_existe
  from sos_pannes p
  join sos_panne_vehicules pv on pv.panne_code = p.code
  where p.code = v_panne and pv.vehicule_code = v_vehicule
  limit 1;

  if v_existe is null then
    raise exception 'PANNE_INCOMPATIBLE : la panne % n''est pas autorisée pour le véhicule %',
      v_panne, v_vehicule;
  end if;

  -- Pièce éventuellement requise par la panne.
  select sp.piece_code, sp.piece_obligatoire into v_piece_code, v_piece_obl
  from sos_pannes sp
  where sp.code = v_panne;

  -- Compétences requises par la panne.
  select coalesce(array_agg(distinct c.skill_code), '{}') into v_comp
  from sos_panne_competences c
  where c.panne_code = v_panne;

  -- Habilitations requises par tous les services associés à la panne.
  select coalesce(array_agg(distinct h), '{}') into v_hab
  from (
    select unnest(s.habilitations) as h
    from sos_panne_services ps
    join sos_services s on s.code = ps.service_code
    where ps.panne_code = v_panne
  ) hab;

  -- Services de prestation express associés à la panne.
  select coalesce(array_agg(distinct ps.service_code), '{}') into v_services
  from sos_panne_services ps
  where ps.panne_code = v_panne;

  -- Remorquage ? (la panne exige une dépanneuse) → tarif officiel adapté.
  v_remorquage := exists (
    select 1 from sos_panne_services ps
    where ps.panne_code = v_panne
      and ps.service_code like 'DEPANNEUSE%'
  );
  v_tarif_km := coalesce((
    select value_int from public.app_config
    where key = case when v_remorquage
      then 'sos_remorquage_fcfa_km'
      else 'sos_deplacement_express_fcfa_km' end
  ), case when v_remorquage then 400 else 100 end);

  return coalesce(jsonb_agg(
    jsonb_build_object(
      'id',            t.id,
      'nom',           t.nom,
      'business_name', t.business_name,
      'metier',        t.metier,
      'telephone',     t.telephone,
      'note_moyenne',  t.note_moyenne,
      'distance_km',   t.distance_km,
      'rayon_max_km',  t.rayon_max_km,
      'sos_services',  to_jsonb(t.services_match),
      'habilitations', to_jsonb(t.habilitations),
      'competences',   to_jsonb(t.competences),
      'devis', jsonb_build_object(
        'main_oeuvre_fcfa', t.mo_fcfa,
        'piece_code',       v_piece_code,
        'piece_libelle',    t.piece_libelle,
        'piece_prix_fcfa',  t.piece_prix,
        'piece_stock',      t.piece_stock,
        'deplacement_fcfa', t.deplacement_fcfa,
        'total_fcfa',       t.total_fcfa,
        'tarif_km_garanti', v_tarif_km
      )
    ) order by t.total_fcfa asc, t.distance_km asc
  ) filter (where t.id is not null), '[]'::jsonb)
  from (
    select
      p.id,
      p.business_name as nom,
      p.business_name,
      p.metier,
      prof.phone as telephone,
      p.note_moyenne,
      p.rayon_max_km,
      v_tarif_km as tarif_km_fcfa,
      p.habilitations,
      p.sos_services as services_match,
      haversine_km(p.latitude, p.longitude, p_lat, p_lng) as distance_km,
      pn.main_oeuvre_fcfa as mo_fcfa,
      piece.prix_fcfa     as piece_prix,
      piece.stock         as piece_stock,
      piece.libelle       as piece_libelle,
      greatest(
        p.frais_deplacement_min_fcfa,
        ceil(v_tarif_km
             * least(
                 haversine_km(p.latitude, p.longitude, p_lat, p_lng),
                 p.rayon_max_km::numeric
               ) / 50.0)::int * 50
      )::int as deplacement_fcfa,
      (
        pn.main_oeuvre_fcfa
        + coalesce(piece.prix_fcfa, 0)
        + greatest(
            p.frais_deplacement_min_fcfa,
            ceil(v_tarif_km
                 * least(
                     haversine_km(p.latitude, p.longitude, p_lat, p_lng),
                     p.rayon_max_km::numeric
                   ) / 50.0)::int * 50
          )::int
      ) as total_fcfa,
      (
        select array_agg(distinct s.skill_code)
        from provider_skill_codes s
        where s.provider_id = p.id
          and s.valide
          and s.skill_code = any (v_comp)
      ) as competences
    from providers p
    join sos_pannes pn on pn.code = v_panne
    left join profiles prof on prof.id = p.id
    left join lateral (
      select ci.prix_fcfa, ci.stock, ci.piece_libelle as libelle
      from provider_catalog_items ci
      where ci.provider_id = p.id
        and ci.piece_code  = v_piece_code
        and ci.prix_fcfa is not null
        and ci.stock > 0
      order by ci.prix_fcfa asc
      limit 1
    ) piece on true
    where p.disponible is true
      and p.statut_validation = 'approved'
      and not exists (
        select 1 from profiles pf
        where pf.id = p.id and pf.is_suspended
      )
      and not exists (
        select 1 from wallets w
        where w.provider_id = p.id and w.blocked
      )
      and p.vehicle_categories @> array[v_vehicule]
      and p.habilitations @> coalesce(v_hab, '{}'::text[])
      and p.sos_services && coalesce(v_services, '{}'::text[])
      and exists (
        select 1 from provider_skill_codes s
        where s.provider_id = p.id and s.valide and s.skill_code = any (v_comp)
      )
      and (
        v_piece_obl is not true
        or (v_piece_code is not null and piece.stock is not null and piece.stock > 0)
      )
      and haversine_km(p.latitude, p.longitude, p_lat, p_lng)
            <= least(p_rayon_km, p.rayon_max_km::numeric)
    order by
      haversine_km(p.latitude, p.longitude, p_lat, p_lng) asc
    limit greatest(1, least(coalesce(p_limit, 5), 20))
  ) t;
end;
$func$;

revoke all on function sos_match_providers(text, text, double precision, double precision, numeric, int) from public;
grant execute on function sos_match_providers(text, text, double precision, double precision, numeric, int)
  to anon, authenticated;

-- ----------------------------------------------------------------------------
-- 4. Nouveaux métiers reconnus (remorquage, lavage, carburant)
-- ----------------------------------------------------------------------------
create or replace function public.provider_kind_from_metier(p_metier text)
returns text
language sql
immutable
as $$
  select case
    when lower(coalesce(p_metier, '')) like '%zemidjan%'
      or lower(coalesce(p_metier, '')) like '%zémidjan%'      then 'zemidjan'
    when lower(coalesce(p_metier, '')) like '%tricycle%'      then 'tricycle_fret'
    when lower(coalesce(p_metier, '')) like '%remorquage%'
      or lower(coalesce(p_metier, '')) like '%dépanneuse%'
      or lower(coalesce(p_metier, '')) like '%depanneuse%'    then 'remorquage'
    when lower(coalesce(p_metier, '')) like '%vulcanis%'
      or lower(coalesce(p_metier, '')) like '%pneu%'          then 'vulcanisateur'
    when lower(coalesce(p_metier, '')) like '%électric%'
      or lower(coalesce(p_metier, '')) like '%electric%'      then 'electricien'
    when lower(coalesce(p_metier, '')) like '%essence%'
      or lower(coalesce(p_metier, '')) like '%carburant%'
      or lower(coalesce(p_metier, '')) like '%station%'       then 'station'
    when lower(coalesce(p_metier, '')) like '%lavage%'        then 'lavage'
    when lower(coalesce(p_metier, '')) like '%garage%'        then 'garage'
    else 'mecanicien'
  end;
$$;

commit;

-- ── Contrôles (à exécuter après le script) ──
-- SELECT key, value_int FROM public.app_config
--  WHERE key LIKE 'ride_%' OR key LIKE 'sos_%' ORDER BY key;
-- attendu : zemidjan 150, cloboto 200, kloboto 300, express 100, remorquage 400.
