-- ============================================================================
-- MonTotem — SOS PANNE : Script 10/10
-- Vérification exhaustive du module SOS. À exécuter en DERNIER.
-- Ne modifie aucune donnée : comptages + contrôles d'intégrité.
--
-- Contrôles attendus (conformes à la spécification) :
--   - 14 véhicules, 18 pannes, 63 paires panne↔véhicule ;
--   - 13 compétences, 8 services, 3 habilitations ;
--   - 3 RPC SOS présentes ;
--   - RLS activée sur les 11 tables SOS ;
--   - sos_interventions vivante et fonctionnelle.
-- Échec = exception explicite avec le détail manquant.
-- ============================================================================

begin;

do $verif$
declare
  v_nb_vehicules        int;
  v_nb_pannes           int;
  v_nb_paires           int;
  v_nb_vehicules_locaux int;
  v_nb_competences      int;
  v_nb_services         int;
  v_nb_habilitations    int;
  v_nb_panne_comp       int;
  v_nb_panne_services   int;
  v_nb_rpc              int;
  v_rls_off             int;
  v_msg                 text := '';
  v_paires_attendues    int := 63;
begin
  -- -------------------------------------------------------------------------
  -- 1. Contenu des référentiels
  -- -------------------------------------------------------------------------
  select count(*) into v_nb_vehicules from sos_vehicules;
  select count(*) into v_nb_pannes from sos_pannes;
  select count(*) into v_nb_paires from sos_panne_vehicules;
  select count(distinct vehicule_code) into v_nb_vehicules_locaux
    from sos_panne_vehicules;
  select count(*) into v_nb_competences from sos_competences;
  select count(*) into v_nb_services from sos_services;
  select count(*) into v_nb_habilitations from sos_habilitations;
  select count(*) into v_nb_panne_comp from sos_panne_competences;
  select count(*) into v_nb_panne_services from sos_panne_services;

  raise notice '== SOS : véhicules % / 14 | pannes % / 18 | compétences % / 13 | services % / 8 | habilitations % / 3 ==',
    v_nb_vehicules, v_nb_pannes, v_nb_competences, v_nb_services, v_nb_habilitations;
  raise notice '== SOS : paires véhicule↔panne % / 63 (véhicules couverts : %) | liens panne↔compétence % | panne↔service % ==',
    v_nb_paires, v_nb_vehicules_locaux, v_nb_panne_comp, v_nb_panne_services;

  if v_nb_vehicules <> 14 then
    v_msg := v_msg || format(E'\n  - véhicules : %s au lieu de 14', v_nb_vehicules);
  end if;
  if v_nb_pannes <> 18 then
    v_msg := v_msg || format(E'\n  - pannes : %s au lieu de 18', v_nb_pannes);
  end if;
  if v_nb_paires <> v_paires_attendues then
    v_msg := v_msg || format(E'\n  - paires véhicule↔panne : %s au lieu de %s', v_nb_paires, v_paires_attendues);
  end if;
  if v_nb_vehicules_locaux <> 14 then
    v_msg := v_msg || format(E'\n  - véhicules couverts par la matrice : %s au lieu de 14', v_nb_vehicules_locaux);
  end if;
  if v_nb_competences <> 13 then
    v_msg := v_msg || format(E'\n  - compétences : %s au lieu de 13', v_nb_competences);
  end if;
  if v_nb_services <> 8 then
    v_msg := v_msg || format(E'\n  - services : %s au lieu de 8', v_nb_services);
  end if;
  if v_nb_habilitations <> 3 then
    v_msg := v_msg || format(E'\n  - habilitations : %s au lieu de 3', v_nb_habilitations);
  end if;
  if v_nb_panne_comp < 18 then
    v_msg := v_msg || format(E'\n  - liens panne↔compétence trop peu nombreux : %s (attendu >= 18, une par panne)', v_nb_panne_comp);
  end if;
  if v_nb_panne_services < 18 then
    v_msg := v_msg || format(E'\n  - liens panne↔service trop peu nombreux : %s (attendu >= 18, une par panne)', v_nb_panne_services);
  end if;

  -- Chaque panne doit avoir au moins une compétence ET un service.
  if exists (
    select 1 from sos_pannes p
    where not exists (select 1 from sos_panne_competences c where c.panne_code = p.code)
       or not exists (select 1 from sos_panne_services s where s.panne_code = p.code)
  ) then
    v_msg := v_msg || E'\n  - au moins une panne n''a ni compétence ni service associé';
  end if;

  -- -------------------------------------------------------------------------
  -- 2. Tables techniques + RLS
  -- -------------------------------------------------------------------------
  if to_regclass('public.sos_interventions') is null then
    v_msg := v_msg || E'\n  - table sos_interventions absente (script 05 non exécuté)';
  end if;
  if to_regclass('public.provider_skill_codes') is null then
    v_msg := v_msg || E'\n  - table provider_skill_codes absente (script 04 non exécuté)';
  end if;

  select count(*) into v_rls_off
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in (
      'sos_niveaux_securite', 'sos_vehicules', 'sos_habilitations',
      'sos_competences', 'sos_services', 'sos_pannes',
      'sos_panne_vehicules', 'sos_panne_competences', 'sos_panne_services',
      'sos_interventions', 'provider_skill_codes'
    )
    and not c.relrowsecurity;
  if v_rls_off > 0 then
    v_msg := v_msg || format(E'\n  - RLS non activée sur %s table(s) du module SOS (script 09 non exécuté)', v_rls_off);
  end if;

  -- -------------------------------------------------------------------------
  -- 3. RPC SOS présentes
  -- -------------------------------------------------------------------------
  select count(*) into v_nb_rpc
  from pg_proc pr
  join pg_namespace n on n.oid = pr.pronamespace
  where n.nspname = 'public'
    and pr.proname in (
      'sos_pannes_pour_vehicule',
      'sos_match_providers',
      'sos_demander_intervention'
    );
  if v_nb_rpc < 3 then
    v_msg := v_msg || format(E'\n  - RPC SOS présentes : %s / 3', v_nb_rpc);
  end if;
  raise notice '== SOS : RPC présentes % / 3 ==', v_nb_rpc;

  -- -------------------------------------------------------------------------
  -- 4. Bilan
  -- -------------------------------------------------------------------------
  if v_msg <> '' then
    raise exception 'VERIFICATION_SOS_ECHOUEE :%s', v_msg;
  end if;

  raise notice '== SOS : VÉRIFICATION COMPLÈTE RÉUSSIE — module « Je Suis En Panne » prêt ==';
end;
$verif$;

commit;