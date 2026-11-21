-- ============================================================================
-- MonTotem — SOS PANNE : Script 07/10
-- RPC sos_match_providers : matching strict des prestataires + devis
-- transparent pré-calculé côté serveur.
--
-- Règle clé (spéc §3) — un prestataire est retourné SI ET SEULEMENT SI :
--   (1) disponible is true et statut_validation = 'approved'
--       (équivalent fonctionnel de status = 'ONLINE'),
--   (2) au moins une compétence VALIDÉE (provider_skill_codes.valide)
--       correspondant à la panne,
--   (3) vehicle_categories couvre le code véhicule ET toutes les
--       habilitations requises par les services de la panne,
--   (4) si la panne exige une pièce : en stock et prix défini dans son
--       catalogue (provider_catalog_items.piece_code),
--   (5) mêmes règles de protection que providers_nearest (045) :
--       pas de profil suspendu (profiles.is_suspended), wallet non bloqué,
--   (6) distance (haversine_km, script 05) <= min(rayon demandé, rayon_max_km).
--
-- Devis : main_oeuvre + pièce + déplacement = max(frais minimum,
--   tarif_km × km, arrondi à 50 FCFA) — même règle que TravelFee.estimate
--   et providers_nearest (Dart + SQL côté projet).
--
-- Exécution : après les scripts 01-06. Non destructif, idempotent.
-- Prérequis : 03, 04 ; fonction haversine_km (script 05 du projet).
-- ============================================================================

begin;

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
        'tarif_km_garanti', t.tarif_km_fcfa
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
      p.tarif_km_fcfa,
      p.habilitations,
      p.sos_services as services_match,
      haversine_km(p.latitude, p.longitude, p_lat, p_lng) as distance_km,
      pn.main_oeuvre_fcfa as mo_fcfa,
      piece.prix_fcfa     as piece_prix,
      piece.stock         as piece_stock,
      piece.libelle       as piece_libelle,
      greatest(
        p.frais_deplacement_min_fcfa,
        ceil(p.tarif_km_fcfa
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
            ceil(p.tarif_km_fcfa
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

commit;