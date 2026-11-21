-- ============================================================================
-- MonTotem — SOS PANNE : Script 05/10
-- Table des demandes d'intervention SOS (devis figé côté serveur).
--
-- Exécution : après les scripts 01-04. Non destructif, idempotent.
-- Prérequis : 01 (sos_vehicules, sos_niveaux_securite), 03 (sos_pannes),
--             profiles, providers.
-- ============================================================================

begin;

create table if not exists sos_interventions (
  id              uuid primary key default gen_random_uuid(),
  client_id       uuid not null references profiles (id) on delete cascade,
  prestataire_id  uuid references providers (id) on delete set null,
  vehicule_code   text not null references sos_vehicules (code),
  panne_code      text not null references sos_pannes (code),
  niveau_securite text references sos_niveaux_securite (code),
  gps_lat         double precision not null
                  check (gps_lat between -90 and 90),
  gps_lng         double precision not null
                  check (gps_lng between -180 and 180),
  repere_local    text,
  devis           jsonb not null default '{}'::jsonb,
  statut          text not null default 'ENVOYEE'
                  check (statut in ('ENVOYEE', 'ANNULEE', 'ATTACHEE')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists sos_interventions_client_idx
  on sos_interventions (client_id, created_at desc);

create index if not exists sos_interventions_prestataire_idx
  on sos_interventions (prestataire_id, created_at desc);

commit;