-- ============================================================================
-- MonTotem — SOS PANNE : Script 09/10
-- Sécurité par ligne (RLS) et droits (GRANT) pour l'ensemble des 8 tables
-- référentielles + sos_interventions + provider_skill_codes.
--
-- Modèle appliqué (cohérent avec 050_rls_policies du projet) :
--   - tables de référentiel (niveaux, véhicules, habilitations, compétences,
--     services, pannes, matrices) : lecture publique, écriture admin
--     uniquement ;
--   - sos_interventions : le client voit et crée SES demandes, le
--     prestataire voit les demandes qui lui sont adressées et peut y changer
--     le statut (ATTACHEE / ANNULEE), l'admin a tous les droits ;
--   - provider_skill_codes : lecture publique des compétences VALIDÉES, le
--     prestataire gère les siennes via auth.uid() = providers.id, l'admin
--     complète et valide.
--
-- Exécution : après les scripts 01-08. Non destructif, idempotent
-- (drop policy if exists ... on <table> avant chaque create policy).
-- Prérequis : 01-05 (tables), 10_profiles_admin (is_admin()).
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Tables de référentiel : lecture publique, écriture admin
-- ---------------------------------------------------------------------------
alter table sos_niveaux_securite   enable row level security;
alter table sos_vehicules          enable row level security;
alter table sos_habilitations      enable row level security;
alter table sos_competences        enable row level security;
alter table sos_services           enable row level security;
alter table sos_pannes             enable row level security;
alter table sos_panne_vehicules    enable row level security;
alter table sos_panne_competences  enable row level security;
alter table sos_panne_services     enable row level security;

drop policy if exists sos_niveaux_securite_lecture
  on sos_niveaux_securite;
create policy sos_niveaux_securite_lecture
  on sos_niveaux_securite for select
  using (true);

drop policy if exists sos_vehicules_lecture
  on sos_vehicules;
create policy sos_vehicules_lecture
  on sos_vehicules for select
  using (true);

drop policy if exists sos_habilitations_lecture
  on sos_habilitations;
create policy sos_habilitations_lecture
  on sos_habilitations for select
  using (true);

drop policy if exists sos_competences_lecture
  on sos_competences;
create policy sos_competences_lecture
  on sos_competences for select
  using (true);

drop policy if exists sos_services_lecture
  on sos_services;
create policy sos_services_lecture
  on sos_services for select
  using (true);

drop policy if exists sos_pannes_lecture
  on sos_pannes;
create policy sos_pannes_lecture
  on sos_pannes for select
  using (true);

drop policy if exists sos_panne_vehicules_lecture
  on sos_panne_vehicules;
create policy sos_panne_vehicules_lecture
  on sos_panne_vehicules for select
  using (true);

drop policy if exists sos_panne_competences_lecture
  on sos_panne_competences;
create policy sos_panne_competences_lecture
  on sos_panne_competences for select
  using (true);

drop policy if exists sos_panne_services_lecture
  on sos_panne_services;
create policy sos_panne_services_lecture
  on sos_panne_services for select
  using (true);

-- Écriture des référentiels réservée à l'admin (authentifié).
drop policy if exists sos_referentiel_admin
  on sos_niveaux_securite;
create policy sos_referentiel_admin
  on sos_niveaux_securite for all
  to authenticated
  using (is_admin())
  with check (is_admin());

drop policy if exists sos_referentiel_admin
  on sos_vehicules;
create policy sos_referentiel_admin
  on sos_vehicules for all
  to authenticated
  using (is_admin())
  with check (is_admin());

drop policy if exists sos_referentiel_admin
  on sos_habilitations;
create policy sos_referentiel_admin
  on sos_habilitations for all
  to authenticated
  using (is_admin())
  with check (is_admin());

drop policy if exists sos_referentiel_admin
  on sos_competences;
create policy sos_referentiel_admin
  on sos_competences for all
  to authenticated
  using (is_admin())
  with check (is_admin());

drop policy if exists sos_referentiel_admin
  on sos_services;
create policy sos_referentiel_admin
  on sos_services for all
  to authenticated
  using (is_admin())
  with check (is_admin());

drop policy if exists sos_referentiel_admin
  on sos_pannes;
create policy sos_referentiel_admin
  on sos_pannes for all
  to authenticated
  using (is_admin())
  with check (is_admin());

drop policy if exists sos_referentiel_admin
  on sos_panne_vehicules;
create policy sos_referentiel_admin
  on sos_panne_vehicules for all
  to authenticated
  using (is_admin())
  with check (is_admin());

drop policy if exists sos_referentiel_admin
  on sos_panne_competences;
create policy sos_referentiel_admin
  on sos_panne_competences for all
  to authenticated
  using (is_admin())
  with check (is_admin());

drop policy if exists sos_referentiel_admin
  on sos_panne_services;
create policy sos_referentiel_admin
  on sos_panne_services for all
  to authenticated
  using (is_admin())
  with check (is_admin());

-- ---------------------------------------------------------------------------
-- 2. sos_interventions : propriétaire (client) / prestataire / admin
-- ---------------------------------------------------------------------------
alter table sos_interventions enable row level security;

drop policy if exists sos_interventions_lecture
  on sos_interventions;
create policy sos_interventions_lecture
  on sos_interventions for select
  to authenticated
  using (
    client_id = auth.uid()
    or is_admin()
    or prestataire_id = auth.uid()
  );

drop policy if exists sos_interventions_proprietaire
  on sos_interventions;
create policy sos_interventions_proprietaire
  on sos_interventions for insert
  to authenticated
  with check (client_id = auth.uid());

-- Le client peut uniquement annuler sa demande.
drop policy if exists sos_interventions_annulation
  on sos_interventions;
create policy sos_interventions_annulation
  on sos_interventions for update
  to authenticated
  using (client_id = auth.uid())
  with check (client_id = auth.uid() and statut = 'ANNULEE');

-- Le prestataire concerné peut attacher (accepter) ou refuser.
drop policy if exists sos_interventions_prestataire
  on sos_interventions;
create policy sos_interventions_prestataire
  on sos_interventions for update
  to authenticated
  using (
    prestataire_id is not null
    and prestataire_id = auth.uid()
    and exists (
      select 1 from providers pv
      where pv.id = auth.uid()
        and pv.statut_validation = 'approved'
    )
  )
  with check (
    prestataire_id = auth.uid()
    and statut in ('ATTACHEE', 'ANNULEE')
  );

drop policy if exists sos_interventions_admin
  on sos_interventions;
create policy sos_interventions_admin
  on sos_interventions for all
  to authenticated
  using (is_admin())
  with check (is_admin());

-- ---------------------------------------------------------------------------
-- 3. provider_skill_codes : public voit le validé, prestataire gère le sien
-- ---------------------------------------------------------------------------
alter table provider_skill_codes enable row level security;

drop policy if exists provider_skill_codes_public
  on provider_skill_codes;
create policy provider_skill_codes_public
  on provider_skill_codes for select
  using (
    valide
    or is_admin()
    or provider_id = auth.uid()
  );

drop policy if exists provider_skill_codes_proprio
  on provider_skill_codes;
create policy provider_skill_codes_proprio
  on provider_skill_codes for all
  to authenticated
  using (
    exists (
      select 1 from providers pv
      where pv.id = provider_id
        and pv.id = auth.uid()
    )
    or is_admin()
  )
  with check (
    exists (
      select 1 from providers pv
      where pv.id = provider_id
        and pv.id = auth.uid()
    )
    or is_admin()
  );

-- ---------------------------------------------------------------------------
-- 4. Tables SOS ouvertes en lecture directe aux rôles Supabase
-- ---------------------------------------------------------------------------
grant select on sos_niveaux_securite  to anon, authenticated;
grant select on sos_vehicules         to anon, authenticated;
grant select on sos_habilitations     to anon, authenticated;
grant select on sos_competences       to anon, authenticated;
grant select on sos_services          to anon, authenticated;
grant select on sos_pannes            to anon, authenticated;
grant select on sos_panne_vehicules   to anon, authenticated;
grant select on sos_panne_competences to anon, authenticated;
grant select on sos_panne_services    to anon, authenticated;

grant select, insert, update on sos_interventions to authenticated;
grant select, insert, update, delete on provider_skill_codes to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Droits d'exécution sur les 3 RPC SOS (rappel idempotent)
-- ---------------------------------------------------------------------------
revoke all on function sos_pannes_pour_vehicule(text) from public;
grant execute on function sos_pannes_pour_vehicule(text)
  to anon, authenticated;

revoke all on function sos_match_providers(text, text, double precision, double precision, numeric, int)
  from public;
grant execute on function sos_match_providers(text, text, double precision, double precision, numeric, int)
  to anon, authenticated;

revoke all on function sos_demander_intervention(text, text, double precision, double precision, uuid, text, text)
  from public;
grant execute on function sos_demander_intervention(text, text, double precision, double precision, uuid, text, text)
  to authenticated;

commit;