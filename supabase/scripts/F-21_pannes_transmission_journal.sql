-- ============================================================================
-- MonTotem — F-21 : PANNES TRANSMISSION + JOURNAL DES PANNES
-- ============================================================================
-- 1. Deux nouvelles pannes de transmission deux-roues :
--      - COURROIE_CASSEE : scooter thermique (juste accélérer, courroie) ;
--      - CHAINE_CASSEE   : moto à vitesses / tricycles (transmission chaîne).
--    Le dépanneur sait ainsi AVANT de partir s'il doit acheter/monter une
--    courroie de scooter ou un kit chaîne.
--
-- 2. Matrice panne ↔ véhicule mise à jour :
--      - SCOOTER_THERM : + COURROIE_CASSEE
--      - ZEM_MOTO      : + CHAINE_CASSEE
--      - CLOBOTO_PAX / KLOBOTO_FRET : + CHAINE_CASSEE
--
-- 3. Description libre de la panne : colonne `description` sur
--    sos_interventions et nouveau paramètre p_description dans
--    sos_demander_intervention (recréée, non destructive).
--
-- 4. JOURNAL DES PANNES : chaque panne décrite par un usager est enregistrée
--    (sos_pannes_journal) pour permettre un diagnostic rapide et des
--    statistiques fiables des pannes rencontrées au quotidien.
--
-- Exécution : dans Supabase SQL Editor (après sos/01..09 et F-20).
-- Non destructif, idempotent.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Nouvelles pannes (référentiel)
-- ---------------------------------------------------------------------------
insert into sos_pannes (code, libelle, description, main_oeuvre_fcfa,
                        piece_obligatoire, piece_code, piece_libelle, position)
values
  ('COURROIE_CASSEE', 'Courroie de scooter cassée (scooter : juste accélérer)',
   'Transmission variateur-courroie : remplacement sur place.', 3500, true,
   'COURROIE_SCOOTER', 'Courroie de transmission scooter', 45),
  ('CHAINE_CASSEE', 'Chaîne cassée (moto à vitesses)',
   'Kit chaîne : dérivation ou remplacement sur place.', 4000, true,
   'KIT_CHAINE_MOTO', 'Kit chaîne moto (chaîne + pignons)', 46)
on conflict (code) do update
  set libelle           = excluded.libelle,
      description       = excluded.description,
      main_oeuvre_fcfa  = excluded.main_oeuvre_fcfa,
      piece_obligatoire = excluded.piece_obligatoire,
      piece_code        = excluded.piece_code,
      piece_libelle     = excluded.piece_libelle,
      position          = excluded.position;

-- ---------------------------------------------------------------------------
-- 2. Matrice panne ↔ véhicule (uniquement les nouvelles paires)
-- ---------------------------------------------------------------------------
insert into sos_panne_vehicules (panne_code, vehicule_code)
values
  ('COURROIE_CASSEE', 'SCOOTER_THERM'),
  ('CHAINE_CASSEE',   'ZEM_MOTO'),
  ('CHAINE_CASSEE',   'CLOBOTO_PAX'),
  ('CHAINE_CASSEE',   'KLOBOTO_FRET')
on conflict (panne_code, vehicule_code) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Description libre sur les interventions SOS
-- ---------------------------------------------------------------------------
alter table sos_interventions
  add column if not exists description text;

-- ---------------------------------------------------------------------------
-- 4. RPC sos_demander_intervention : version avec p_description.
--    (Corps identique au script 08 + stockage de la description.)
-- ---------------------------------------------------------------------------
create or replace function sos_demander_intervention(
  p_vehicule        text,
  p_panne           text,
  p_lat             double precision,
  p_lng             double precision,
  p_prestataire     uuid,
  p_niveau_securite text default null,
  p_repere_local    text default null,
  p_description     text default null
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
  v_desc       text := nullif(btrim(coalesce(p_description, '')), '');
  v_match      jsonb;
  v_element    jsonb;
  v_devis      jsonb;
  v_trouve     boolean := false;
  v_id         uuid;
begin
  -- 1. Client connecté obligatoire.
  if v_client is null then
    raise exception 'NON_CONNECTE : vous devez être connecté pour commander une intervention';
  end if;

  -- 2. Matching strict : le prestataire demandé doit sortir du filtre.
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

  -- 3. Insertion avec devis figé + description du client.
  insert into sos_interventions (
    client_id, prestataire_id, vehicule_code, panne_code,
    niveau_securite, gps_lat, gps_lng, repere_local, devis, statut,
    description
  ) values (
    v_client, p_prestataire, v_vehicule, v_panne,
    v_niveau, p_lat, p_lng, v_repere, v_devis, 'ENVOYEE',
    v_desc
  )
  returning id into v_id;

  return v_id;
end;
$func$;

revoke all on function sos_demander_intervention(text, text, double precision, double precision, uuid, text, text)
  from public;
revoke all on function sos_demander_intervention(text, text, double precision, double precision, uuid, text, text, text)
  from public;
grant execute on function sos_demander_intervention(text, text, double precision, double precision, uuid, text, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Journal des pannes : TOUTES les pannes rencontrées par les usagers
-- ---------------------------------------------------------------------------
create table if not exists sos_pannes_journal (
  id            uuid primary key default gen_random_uuid(),
  client_id     uuid references profiles (id) on delete set null,
  vehicule_code text not null,
  panne_code    text not null,
  description   text,
  gps_lat       double precision check (gps_lat is null or gps_lat between -90 and 90),
  gps_lng       double precision check (gps_lng is null or gps_lng between -180 and 180),
  created_at    timestamptz not null default now()
);

-- Statistiques de diagnostic rapide : pannes les plus fréquentes récentes.
create index if not exists sos_pannes_journal_panne_idx
  on sos_pannes_journal (panne_code, created_at desc);
create index if not exists sos_pannes_journal_vehicule_idx
  on sos_pannes_journal (vehicule_code, created_at desc);

alter table sos_pannes_journal enable row level security;

-- Lecture réservée aux administrateurs (poste de travail admin).
drop policy if exists sos_pannes_journal_read_admin on sos_pannes_journal;
create policy sos_pannes_journal_read_admin
  on sos_pannes_journal for select
  using (public.is_admin());

-- RPC de journalisation : chaque usager enregistre SA panne uniquement.
create or replace function sos_journaliser_panne(
  p_vehicule    text,
  p_panne       text,
  p_description text default null,
  p_lat         double precision default null,
  p_lng         double precision default null
) returns void
language sql
volatile
security definer
set search_path = public
as $func$
  insert into sos_pannes_journal (
    client_id, vehicule_code, panne_code, description, gps_lat, gps_lng
  ) values (
    auth.uid(),
    upper(btrim(p_vehicule)),
    upper(btrim(p_panne)),
    nullif(btrim(coalesce(p_description, '')), ''),
    p_lat,
    p_lng
  );
$func$;

revoke all on function sos_journaliser_panne(text, text, text, double precision, double precision)
  from public;
grant execute on function sos_journaliser_panne(text, text, text, double precision, double precision)
  to authenticated;

commit;
