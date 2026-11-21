-- ============================================================================
-- MonTotem — SOS PANNE : Script 08/10
-- RPC sos_demander_intervention : enregistre la demande d'intervention du
-- client (Étape 4 — commande) avec le devis garanti recalculé côté serveur.
--
-- Sécurité :
--   - le client doit être connecté (auth.uid() non null) ;
--   - le prestataire demandé doit sortir du matching strict
--     sos_match_providers (script 07) : le devis renvoyé est inclus dans le
--     retour du matching, donc impossible de commander un devis forgé côté
--     client ;
--   - le niveau de sécurité est normalisé (UPPER/TRIM) et validé par la
--     clé étrangère vers sos_niveaux_securite.
--
-- Exécution : après les scripts 01-07. Non destructif, idempotent.
-- NB : volatile (et non stable) car la fonction insère une ligne avec le
--      devis figé. Prérequis : 05 (sos_interventions), 07 (sos_match_providers).
-- ============================================================================

begin;

create or replace function sos_demander_intervention(
  p_vehicule        text,
  p_panne           text,
  p_lat             double precision,
  p_lng             double precision,
  p_prestataire     uuid,
  p_niveau_securite text default null,
  p_repere_local    text default null
) returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $func$
declare
  v_client     uuid := auth.uid();
  v_vehicule   text := upper(btrim(p_vehicule));
  v_panne      text := upper(btrim(p_panne));
  v_niveau     text := nullif(upper(btrim(coalesce(p_niveau_securite, ''))), '');
  v_repere     text := nullif(btrim(coalesce(p_repere_local, '')), '');
  v_match      jsonb;
  v_element    jsonb;
  v_devis      jsonb;
  v_trouve     boolean := false;
  v_id         uuid;
begin
  -- 1. Client connecté obligatoire (SECURITY DEFINER : contrôle explicite).
  if v_client is null then
    raise exception 'NON_CONNECTE : vous devez être connecté pour commander une intervention';
  end if;

  -- 2. Matching strict (règle clé de la spécification) : le prestataire
  --    demandé doit figurer dans le résultat filtré. Rayon 15 km, limite 20
  --    : mêmes ordres de grandeur que l'affichage client.
  v_match := sos_match_providers(v_vehicule, v_panne, p_lat, p_lng, 15, 20);

  if jsonb_typeof(v_match) is distinct from 'array' or v_match = '[]'::jsonb then
    raise exception 'AUCUN_PRESTATAIRE : aucun prestataire compatible autour de votre position';
  end if;

  for v_element in select * from jsonb_array_elements(v_match)
  loop
    if (v_element ->> 'id')::uuid = p_prestataire then
      v_devis  := v_element -> 'devis';
      v_trouve := true;
      exit;
    end if;
  end loop;

  if not v_trouve then
    raise exception 'PRESTATAIRE_INCOMPATIBLE : ce prestataire ne répond pas aux critères de votre panne';
  end if;

  -- 3. Insertion avec devis figé (garanti côté serveur, jamais client).
  insert into sos_interventions (
    client_id, prestataire_id, vehicule_code, panne_code,
    niveau_securite, gps_lat, gps_lng, repere_local, devis, statut
  ) values (
    v_client, p_prestataire, v_vehicule, v_panne,
    v_niveau, p_lat, p_lng, v_repere, v_devis, 'ENVOYEE'
  )
  returning id into v_id;

  return v_id;
end;
$func$;

revoke all on function sos_demander_intervention(text, text, double precision, double precision, uuid, text, text)
  from public;
grant execute on function sos_demander_intervention(text, text, double precision, double precision, uuid, text, text)
  to authenticated;

commit;