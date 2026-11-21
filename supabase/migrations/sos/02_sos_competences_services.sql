-- ============================================================================
-- MonTotem — SOS PANNE : Script 02/10
-- Référentiel des habilitations, des compétences (required_skill_code) et des
-- services de prestation express.
--
-- Exécution : après le script 01. Non destructif, idempotent.
-- Prérequis : 01.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Habilitations réglementaires
-- ---------------------------------------------------------------------------
create table if not exists sos_habilitations (
  code    text primary key,
  libelle text not null
);

insert into sos_habilitations (code, libelle) values
  ('HAB_ELECTRIQUE',    'Habilitation Électrique'),
  ('HAB_DEPANNEUSE_VL', 'Dépanneuse Véhicule Léger'),
  ('HAB_DEPANNEUSE_PL', 'Dépanneuse Poids Lourd')
on conflict (code) do update set libelle = excluded.libelle;

-- ---------------------------------------------------------------------------
-- 2. Compétences (required_skill_code) — distinction stricte outillage VL vs PL
-- ---------------------------------------------------------------------------
create table if not exists sos_competences (
  code    text primary key check (code ~ '^[A-Z0-9_]+$'),
  libelle text not null
);

insert into sos_competences (code, libelle) values
  ('PNEU_MOTO',         'Vulcanisateur moto / deux-trois roues'),
  ('PNEU_VL',           'Vulcanisateur véhicules légers'),
  ('PNEU_PL',           'Vulcanisateur Poids Lourd (équipement lourd tonnage)'),
  ('ELEC_AUTO',         'Électricien auto & moto (12V)'),
  ('ELEC_VEHICULE_HAB', 'Technicien véhicules électriques (BMS / contrôleur)'),
  ('MECANIQUE_MOTO',    'Mécanicien moto / deux-trois roues'),
  ('MECANIQUE_VL',      'Mécanicien véhicules légers'),
  ('MECA_LOURDE_PL',    'Mécanicien Poids Lourd (camion-atelier)'),
  ('FREIN_AIR_PL',      'Circuit d''air & freinage pneumatique PL'),
  ('DIAG_24V_PL',       'Diagnostic & démarrage 24V Poids Lourd'),
  ('REMORQUAGE_VL',     'Remorquage / dépanneuse VL'),
  ('REMORQUAGE_PL',     'Remorquage Poids Lourd (dépanneuse lourd tonnage)'),
  ('SWAP_BATTERIE',     'Échange / swap de batterie électrique')
on conflict (code) do update set libelle = excluded.libelle;

-- ---------------------------------------------------------------------------
-- 3. Services de prestation express + habilitations requises
-- ---------------------------------------------------------------------------
create table if not exists sos_services (
  code          text primary key,
  libelle       text not null,
  habilitations text[] not null default '{}'
);

insert into sos_services (code, libelle, habilitations) values
  ('VULCANISATEUR_EXPRESS', 'Vulcanisateur express mobile',                    '{}'),
  ('ATELIER_MOBILE_LEGER',  'Atelier mobile léger / technicien',               '{}'),
  ('TECH_ELECTRIQUE',       'Prestataire certifié électrique / swap',          '{HAB_ELECTRIQUE}'),
  ('GARAGE_MECANIQUE',      'Garage / mécanique générale',                     '{}'),
  ('DEPANNEUSE_VL',         'Dépanneuse Véhicule Léger (remorquage)',          '{HAB_DEPANNEUSE_VL}'),
  ('VULCANISATEUR_PL',      'Vulcanisateur mobile Poids Lourd',                '{}'),
  ('CAMION_ATELIER_PL',     'Mécanicien PL mobile / camion-atelier sur site',  '{}'),
  ('DEPANNEUSE_PL',         'Dépanneuse Poids Lourd (remorquage lourd tonnage)','{HAB_DEPANNEUSE_PL}')
on conflict (code) do update
  set libelle       = excluded.libelle,
      habilitations = excluded.habilitations;

commit;