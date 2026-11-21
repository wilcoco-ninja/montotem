-- ============================================================================
-- MonTotem — Migration 20260415000001 : Module « SOS Je Suis En Panne »
--
-- Idempotente et non destructive : `create table if not exists`,
-- `alter table ... add column if not exists`, `on conflict do update`.
-- Ne modifie aucune colonne existante de type destructif.
--
-- Contenu :
--   1. Référentiel véhicules SOS (codes exacts de la spécification).
--   2. Référentiel pannes + matrice panne ↔ véhicule (filtrage strict).
--   3. Référentiel compétences (required_skill_code), services express,
--      habilitations, niveaux de sécurité de la chaussée.
--   4. Extension du profil prestataire (vehicle_categories, habilitations,
--      sos_services, compétences par code, pièces/stock dans le catalogue).
--   5. RPC : sos_pannes_pour_vehicule, sos_match_providers (matching + pré-di
--      vis transparent), sos_demander_intervention (commande).
--   6. Tables sos_interventions + RLS.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Niveaux de sécurité de la chaussée (Étape 1 du parcours)
-- ---------------------------------------------------------------------------
create table if not exists sos_niveaux_securite (
  code     text primary key check (code in ('OK', 'ATTENTION', 'DANGER')),
  libelle  text not null,
  consigne text not null default '',
  position int  not null default 0
);

insert into sos_niveaux_securite (code, libelle, consigne, position) values
  ('OK',        'Route normale',
   'Garez-vous hors de la chaussée, triangle à 25 m.', 0),
  ('ATTENTION', 'Trafic proche / voie étroite',
   'Gilet puis triangle à 50 m. Restez derrière la barrière si possible.', 1),
  ('DANGER',    'Voie rapide / zone dangereuse',
   'Ne restez pas dans le véhicule. Éloignez-vous derrière une protection.', 2)
on conflict (code) do update
  set libelle  = excluded.libelle,
      consigne = excluded.consigne,
      position = excluded.position;

-- ---------------------------------------------------------------------------
-- 2. Référentiel des véhicules SOS (Étape 2 — codes exacts)
-- ---------------------------------------------------------------------------
create table if not exists sos_vehicules (
  code     text primary key check (code ~ '^[A-Z0-9_]+$'),
  libelle  text not null,
  detail   text not null default '',
  groupe   text not null check (groupe in
             ('DEUX_ROUES', 'TROIS_ROUES', 'QUATRE_ROUES', 'POIDS_LOURD')),
  thermique boolean not null default true,
  position int not null default 0
);

insert into sos_vehicules (code, libelle, detail, groupe, thermique, position) values
  ('ZEM_MOTO',      'Moto classique',            'Motos et cyclomoteurs',          'DEUX_ROUES',  true,  10),
  ('E_MOTO',        'Moto électrique',           'Recharge / swap batterie',       'DEUX_ROUES',  false, 20),
  ('SCOOTER_THERM', 'Scooter mécanique',         'Scooters thermiques',            'DEUX_ROUES',  true,  30),
  ('E_SCOOTER',     'Scooter électrique',        'Scooters électriques',           'DEUX_ROUES',  false, 40),
  ('CLOBOTO_PAX',   'Tricycle passager',         'Cloboto transport de personnes', 'TROIS_ROUES', true,  50),
  ('KLOBOTO_FRET',  'Tricycle fret/bagage',      'Kloboto transport de marchandises', 'TROIS_ROUES', true, 60),
  ('CAR_THERM',     'Voiture thermique',         'Essence / diesel',               'QUATRE_ROUES', true, 70),
  ('E_CAR',         'Voiture électrique/hybride', 'BMS, contrôleur, charge',       'QUATRE_ROUES', false, 80),
  ('UTILITAIRE_VAN','Utilitaire',                'Vans, fourgons, utilitaires',    'QUATRE_ROUES', true,  90),
  ('MINIBUS',       'Minibus',                   'Transport collectif léger',      'QUATRE_ROUES', true,  100),
  ('BUS_TRANSPORT', 'Bus',                       'Transport collectif',            'QUATRE_ROUES', true,  110),
  ('CAMION_6_ROUES','Camion léger / Porteur 6 roues', 'Kia/Hyundai/Canter — tonnage moyen', 'POIDS_LOURD', true, 120),
  ('CAMION_10_ROUES','Camion lourd 10 roues / Benne', 'Tonnage lourd',             'POIDS_LOURD', true, 130),
  ('SEMI_REMORQUE', 'Tracteur routier / Semi-remorque', '12 roues et plus',        'POIDS_LOURD', true, 140)
on conflict (code) do update
  set libelle   = excluded.libelle,
      detail    = excluded.detail,
      groupe    = excluded.groupe,
      thermique = excluded.thermique,
      position  = excluded.position;

-- ---------------------------------------------------------------------------
-- 3. Référentiel des compétences (required_skill_code) et habilitations
-- ---------------------------------------------------------------------------
create table if not exists sos_habilitations (
  code    text primary key,
  libelle text not null
);

insert into sos_habilitations (code, libelle) values
  ('HAB_ELECTRIQUE',   'Habilitation Électrique'),
  ('HAB_DEPANNEUSE_VL','Dépanneuse Véhicule Léger'),
  ('HAB_DEPANNEUSE_PL','Dépanneuse Poids Lourd')
on conflict (code) do update set libelle = excluded.libelle;

create table if not exists sos_competences (
  code    text primary key check (code ~ '^[A-Z0-9_]+$'),
  libelle text not null
);

insert into sos_competences (code, libelle) values
  ('PNEU_MOTO',           'Vulcanisateur moto / deux-trois roues'),
  ('PNEU_VL',             'Vulcanisateur véhicules légers'),
  ('PNEU_PL',             'Vulcanisateur Poids Lourd (équipement lourd tonnage)'),
  ('ELEC_AUTO',           'Électricien auto & moto (12V)'),
  ('ELEC_VEHICULE_HAB',   'Technicien véhicules électriques (BMS / contrôleur)'),
  ('MECANIQUE_MOTO',      'Mécanicien moto / deux-trois roues'),
  ('MECANIQUE_VL',        'Mécanicien véhicules légers'),
  ('MECA_LOURDE_PL',      'Mécanicien Poids Lourd (camion-atelier)'),
  ('FREIN_AIR_PL',        'Circuit d''air & freinage pneumatique PL'),
  ('DIAG_24V_PL',         'Diagnostic & démarrage 24V Poids Lourd'),
  ('REMORQUAGE_VL',       'Remorquage / dépanneuse VL'),
  ('REMORQUAGE_PL',       'Remorquage Poids Lourd (dépanneuse lourd tonnage)'),
  ('SWAP_BATTERIE',       'Échange / swap de batterie électrique')
on conflict (code) do update set libelle = excluded.libelle;

-- ---------------------------------------------------------------------------
-- 4. Référentiel des services de prestation express
-- ---------------------------------------------------------------------------
create table if not exists sos_services (
  code         text primary key,
  libelle      text not null,
  habilitations text[] not null default '{}'
);

insert into sos_services (code, libelle, habilitations) values
  ('VULCANISATEUR_EXPRESS', 'Vulcanisateur express mobile', '{}'),
  ('ATELIER_MOBILE_LEGER',  'Atelier mobile léger / technicien', '{}'),
  ('TECH_ELECTRIQUE',       'Prestataire certifié électrique / swap',
   '{HAB_ELECTRIQUE}'),
  ('GARAGE_MECANIQUE',      'Garage / mécanique générale', '{}'),
  ('DEPANNEUSE_VL',         'Dépanneuse Véhicule Léger (remorquage)',
   '{HAB_DEPANNEUSE_VL}'),
  ('VULCANISATEUR_PL',      'Vulcanisateur mobile Poids Lourd', '{}'),
  ('CAMION_ATELIER_PL',     'Mécanicien PL mobile / camion-atelier sur site', '{}'),
  ('DEPANNEUSE_PL',         'Dépanneuse Poids Lourd (remorquage lourd tonnage)',
   '{HAB_DEPANNEUSE_PL}')
on conflict (code) do update
  set libelle      = excluded.libelle,
      habilitations = excluded.habilitations;

-- ---------------------------------------------------------------------------
-- 5. Référentiel des pannes + matrice panne ↔ véhicule (Étape 3, filtrage strict)
-- ---------------------------------------------------------------------------
create table if not exists sos_pannes (
  code              text primary key check (code ~ '^[A-Z0-9_]+$'),
  libelle           text not null,
  description       text not null default '',
  main_oeuvre_fcfa  int not null default 0,
  piece_obligatoire boolean not null default false,
  piece_code        text,
  piece_libelle     text,
  position          int not null default 0
);

insert into sos_pannes (code, libelle, description, main_oeuvre_fcfa,
                        piece_obligatoire, piece_code, piece_libelle, position) values
  -- Thermique 2/3 roues
  ('CREVAISON_PNEU',        'Crevaison / Pneu / Chambre à air',
   'Tubeless ou chambre à air d''origine.', 2000, true,
   'CHAMBRE_AIR_MOTO', 'Chambre à air / pneu moto', 10),
  ('DEMARRAGE_BATTERIE',    'Panne de démarrage / Batterie / Bougie / Allumage',
   'Diagnostic allumage et charge.', 3000, false,
   'BOUGIE_MOTO', 'Bougie / batterie 12V moto', 20),
  ('TRANSMISSION_CABLE',    'Câble d''embrayage, frein, chaîne ou courroie cassée',
   'Remplacement à l''arrêt.', 3000, false,
   'CABLE_FREIN_MOTO', 'Câble / chaîne / courroie', 30),
  ('SURCHAUFFE_CALAGE',     'Surchauffe ou calage moteur',
   'Diagnostic thermique et redémarrage.', 3000, false, null, null, 40),
  -- Électrique
  ('BATTERIE_VIDE',         'Batterie déchargée / Perte d''autonomie sur la route',
   'Swap ou recharge d''appoint.', 2500, false,
   'BATTERIE_ELEC', 'Batterie / faisceau swap', 50),
  ('BMS_CONTROLEUR',        'Alerte BMS / Contrôleur / Coupure de puissance',
   'Diagnostic électronique habilité.', 4000, false, null, null, 60),
  ('CREVAISON_ROUE_BLOQUEE','Crevaison / Roue bloquée',
   'Pneu tubeless ou roue greffée.', 3000, true,
   'CHAMBRE_AIR_MOTO', 'Chambre à air / pneu', 70),
  ('REMORQUAGE_PLATEAU',    'Remorquage plateau (immobilisation complète)',
   'Plateau VL vers l''atelier le plus proche.', 5000, false, null, null, 80),
  -- Voiture / Utilitaire / Minibus / Bus
  ('BATTERIE_ALTERNATEUR',  'Batterie à plat / Alternateur / Démarreur',
   'Boost ou remplacement.', 4000, false,
   'BATTERIE_VL', 'Batterie 12V véhicule léger', 90),
  ('CREVAISON_VL',          'Crevaison / Éclatement de pneu / Roue de secours absente',
   'Roue de secours ou réparation tubeless.', 3000, false,
   'PNEU_VL', 'Pneu véhicule léger', 100),
  ('SURCHAUFFE_FUITE',      'Surchauffe moteur / Fuite liquide de refroidissement ou huile',
   'Diagnostic et colmatage / durite.', 4500, false, null, null, 110),
  ('FREIN_EMBRAYAGE_COURROIE','Problème freinage, embrayage ou courroie',
   'Remplacement/pièce selon usure.', 4500, false,
   'COURROIE_VL', 'Courroie / plaquettes', 120),
  ('REMORQUAGE_VL',         'Véhicule immobilisé → Dépanneuse / Remorquage',
   'Dépanneuse VL, tarif au km garanti.', 5000, false, null, null, 130),
  -- Poids Lourds
  ('PNEU_PL',               'Pneumatique Poids Lourd : Crevaison / Éclatement pneu jumelé ou essieu',
   'Nécessite cric hydraulique lourd / clé à chocs PL.', 12000, false,
   'VALVE_PL', 'Valve / chambre à air / pneu PL', 140),
  ('FREIN_AIR_PL',          'Circuit d''air & Freinage pneumatique : Chute de pression d''air, fuite flexible, frein de parc bloqué',
   'Intervention sur circuit d''air.', 15000, false,
   'FLEXIBLE_AIR_PL', 'Flexible / valve circuit d''air PL', 150),
  ('ENERGIE_24V',           'Énergie & Démarrage 24V : Batteries 24V à plat (couplage double batterie), alternateur ou démarreur lourd',
   'Couplage double batterie / alternateur.', 12000, false,
   'BATTERIE_24V', 'Batterie 24V PL', 160),
  ('MECA_LOURDE_PL',        'Mécanique lourde & Transmission : Surchauffe moteur / durite éclatée, casse arbre de transmission, embrayage ou boîte de vitesses',
   'Diagnostic PL + intervention', 20000, false, null, null, 170),
  ('REMORQUAGE_PL',         'Immobilisation totale : Remorquage Poids Lourd (dépanneuse lourd tonnage / bras de levage)',
   'Prise en charge lourd tonnage, tarif au km garanti.', 25000, false, null, null, 180)
on conflict (code) do update
  set libelle           = excluded.libelle,
      description       = excluded.description,
      main_oeuvre_fcfa  = excluded.main_oeuvre_fcfa,
      piece_obligatoire = excluded.piece_obligatoire,
      piece_code        = excluded.piece_code,
      piece_libelle     = excluded.piece_libelle,
      position          = excluded.position;

create table if not exists sos_panne_vehicules (
  panne_code    text not null references sos_pannes (code)   on delete cascade,
  vehicule_code text not null references sos_vehicules (code) on delete cascade,
  primary key (panne_code, vehicule_code)
);

-- Matrice exacte de la spécification
insert into sos_panne_vehicules (panne_code, vehicule_code)
select pv.panne_code, v.code
from (values
  -- Moto / Scooter / Tricycle Thermique
  ('ZEM_MOTO',      array['CREVAISON_PNEU','DEMARRAGE_BATTERIE','TRANSMISSION_CABLE','SURCHAUFFE_CALAGE']),
  ('SCOOTER_THERM', array['CREVAISON_PNEU','DEMARRAGE_BATTERIE','TRANSMISSION_CABLE','SURCHAUFFE_CALAGE']),
  ('CLOBOTO_PAX',   array['CREVAISON_PNEU','DEMARRAGE_BATTERIE','TRANSMISSION_CABLE','SURCHAUFFE_CALAGE']),
  ('KLOBOTO_FRET',  array['CREVAISON_PNEU','DEMARRAGE_BATTERIE','TRANSMISSION_CABLE','SURCHAUFFE_CALAGE']),
  -- Électrique
  ('E_MOTO',        array['BATTERIE_VIDE','BMS_CONTROLEUR','CREVAISON_ROUE_BLOQUEE','REMORQUAGE_PLATEAU']),
  ('E_SCOOTER',     array['BATTERIE_VIDE','BMS_CONTROLEUR','CREVAISON_ROUE_BLOQUEE','REMORQUAGE_PLATEAU']),
  ('E_CAR',         array['BATTERIE_VIDE','BMS_CONTROLEUR','CREVAISON_ROUE_BLOQUEE','REMORQUAGE_PLATEAU']),
  -- Quatre roues thermiques
  ('CAR_THERM',     array['BATTERIE_ALTERNATEUR','CREVAISON_VL','SURCHAUFFE_FUITE','FREIN_EMBRAYAGE_COURROIE','REMORQUAGE_VL']),
  ('UTILITAIRE_VAN',array['BATTERIE_ALTERNATEUR','CREVAISON_VL','SURCHAUFFE_FUITE','FREIN_EMBRAYAGE_COURROIE','REMORQUAGE_VL']),
  ('MINIBUS',       array['BATTERIE_ALTERNATEUR','CREVAISON_VL','SURCHAUFFE_FUITE','FREIN_EMBRAYAGE_COURROIE','REMORQUAGE_VL']),
  ('BUS_TRANSPORT', array['BATTERIE_ALTERNATEUR','CREVAISON_VL','SURCHAUFFE_FUITE','FREIN_EMBRAYAGE_COURROIE','REMORQUAGE_VL']),
  -- Poids lourds
  ('CAMION_6_ROUES',array['PNEU_PL','FREIN_AIR_PL','ENERGIE_24V','MECA_LOURDE_PL','REMORQUAGE_PL']),
  ('CAMION_10_ROUES',array['PNEU_PL','FREIN_AIR_PL','ENERGIE_24V','MECA_LOURDE_PL','REMORQUAGE_PL']),
  ('SEMI_REMORQUE', array['PNEU_PL','FREIN_AIR_PL','ENERGIE_24V','MECA_LOURDE_PL','REMORQUAGE_PL'])
) as pv(vehicule_code, pannes)
cross join lateral unnest(pv.pannes) as pn(panne_code)
join sos_vehicules v on v.code = pv.vehicule_code
on conflict (panne_code, vehicule_code) do nothing;

create table if not exists sos_panne_competences (
  panne_code text not null references sos_pannes (code)       on delete cascade,
  skill_code text not null references sos_competences (code)  on delete cascade,
  primary key (panne_code, skill_code)
);

insert into sos_panne_competences (panne_code, skill_code) values
  ('CREVAISON_PNEU',         'PNEU_MOTO'),
  ('CREVAISON_PNEU',         'PNEU_VL'),
  ('DEMARRAGE_BATTERIE',     'ELEC_AUTO'),
  ('DEMARRAGE_BATTERIE',     'MECANIQUE_MOTO'),
  ('TRANSMISSION_CABLE',     'MECANIQUE_MOTO'),
  ('SURCHAUFFE_CALAGE',      'MECANIQUE_MOTO'),
  ('BATTERIE_VIDE',          'ELEC_VEHICULE_HAB'),
  ('BATTERIE_VIDE',          'SWAP_BATTERIE'),
  ('BMS_CONTROLEUR',         'ELEC_VEHICULE_HAB'),
  ('BMS_CONTROLEUR',         'SWAP_BATTERIE'),
  ('CREVAISON_ROUE_BLOQUEE', 'PNEU_MOTO'),
  ('CREVAISON_ROUE_BLOQUEE', 'PNEU_VL'),
  ('REMORQUAGE_PLATEAU',     'REMORQUAGE_VL'),
  ('BATTERIE_ALTERNATEUR',   'ELEC_AUTO'),
  ('BATTERIE_ALTERNATEUR',   'MECANIQUE_VL'),
  ('CREVAISON_VL',           'PNEU_VL'),
  ('SURCHAUFFE_FUITE',       'MECANIQUE_VL'),
  ('FREIN_EMBRAYAGE_COURROIE','MECANIQUE_VL'),
  ('REMORQUAGE_VL',          'REMORQUAGE_VL'),
  ('PNEU_PL',                'PNEU_PL'),
  ('FREIN_AIR_PL',           'FREIN_AIR_PL'),
  ('ENERGIE_24V',            'DIAG_24V_PL'),
  ('MECA_LOURDE_PL',         'MECA_LOURDE_PL'),
  ('REMORQUAGE_PL',          'REMORQUAGE_PL')
on conflict (panne_code, skill_code) do nothing;

create table if not exists sos_panne_services (
  panne_code   text not null references sos_pannes (code)    on delete cascade,
  service_code text not null references sos_services (code)  on delete cascade,
  primary key (panne_code, service_code)
);

insert into sos_panne_services (panne_code, service_code) values
  ('CREVAISON_PNEU',         'VULCANISATEUR_EXPRESS'),
  ('DEMARRAGE_BATTERIE',     'ATELIER_MOBILE_LEGER'),
  ('TRANSMISSION_CABLE',     'ATELIER_MOBILE_LEGER'),
  ('SURCHAUFFE_CALAGE',      'ATELIER_MOBILE_LEGER'),
  ('BATTERIE_VIDE',          'TECH_ELECTRIQUE'),
  ('BMS_CONTROLEUR',         'TECH_ELECTRIQUE'),
  ('BMS_CONTROLEUR',         'DEPANNEUSE_VL'),
  ('CREVAISON_ROUE_BLOQUEE', 'VULCANISATEUR_EXPRESS'),
  ('REMORQUAGE_PLATEAU',     'DEPANNEUSE_VL'),
  ('BATTERIE_ALTERNATEUR',   'ATELIER_MOBILE_LEGER'),
  ('BATTERIE_ALTERNATEUR',   'GARAGE_MECANIQUE'),
  ('CREVAISON_VL',           'VULCANISATEUR_EXPRESS'),
  ('SURCHAUFFE_FUITE',       'ATELIER_MOBILE_LEGER'),
  ('SURCHAUFFE_FUITE',       'GARAGE_MECANIQUE'),
  ('FREIN_EMBRAYAGE_COURROIE','ATELIER_MOBILE_LEGER'),
  ('FREIN_EMBRAYAGE_COURROIE','GARAGE_MECANIQUE'),
  ('REMORQUAGE_VL',          'DEPANNEUSE_VL'),
  ('PNEU_PL',                'VULCANISATEUR_PL'),
  ('FREIN_AIR_PL',           'CAMION_ATELIER_PL'),
  ('ENERGIE_24V',            'CAMION_ATELIER_PL'),
  ('MECA_LOURDE_PL',         'CAMION_ATELIER_PL'),
  ('MECA_LOURDE_PL',         'DEPANNEUSE_PL'),
  ('REMORQUAGE_PL',          'DEPANNEUSE_PL')
on conflict (panne_code, service_code) do nothing;

-- ---------------------------------------------------------------------------
-- 6. Extension du profil prestataire (additif, non destructif)
-- ---------------------------------------------------------------------------
alter table providers
  add column if not exists vehicle_categories text[] not null default '{}';
alter table providers
  add column if not exists habilitations text[] not null default '{}';
alter table providers
  add column if not exists sos_services text[] not null default '{}';
alter table providers
  add column if not exists tarif_km_fcfa int not null default 100
    check (tarif_km_fcfa between 0 and 5000);
alter table providers
  add column if not exists frais_deplacement_min_fcfa int not null default 1000
    check (frais_deplacement_min_fcfa between 0 and 100000);
alter table providers
  add column if not exists rayon_max_km int not null default 15
    check (rayon_max_km between 1 and 50);

create index if not exists providers_vehicle_categories_gin
  on providers using gin (vehicle_categories);

create table if not exists provider_skill_codes (
  provider_id uuid    not null references providers (id) on delete cascade,
  skill_code  text    not null references sos_competences (code) on delete cascade,
  valide      boolean not null default false,
  created_at  timestamptz not null default now(),
  primary key (provider_id, skill_code)
);

create index if not exists provider_skill_codes_skill_idx
  on provider_skill_codes (skill_code) where valide;

-- Pièces / stock dans le catalogue existant du prestataire.
do $$
begin
  if to_regclass('public.provider_catalog_items') is not null then
    execute 'alter table provider_catalog_items
               add column if not exists piece_code text';
    execute 'alter table provider_catalog_items
               add column if not exists piece_libelle text';
    execute 'alter table provider_catalog_items
               add column if not exists stock int not null default 0';
    execute 'create index if not exists provider_catalog_items_piece_idx
               on provider_catalog_items (piece_code)
               where piece_code is not null';
  end if;
end $$;

-- Si provider_kind est un type enum, ajoute sans risque le tricycle passager.
do $$
begin
  if exists (select 1 from pg_type t where t.typname = 'provider_kind') then
    begin
      execute 'alter type provider_kind add value if not exists ''tricycle_pax''';
    exception when others then
      null;
    end;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 7. Demandes d'intervention SOS
-- ---------------------------------------------------------------------------
create table if not exists sos_interventions (
  id               uuid primary key default gen_random_uuid(),
  client_id        uuid not null references profiles (id) on delete cascade,
  prestataire_id   uuid references providers (id) on delete set null,
  vehicule_code    text not null references sos_vehicules (code),
  panne_code       text not null references sos_pannes (code),
  niveau_securite  text references sos_niveaux_securite (code),
  gps_lat          double precision not null,
  gps_lng          double precision not null,
  repere_local     text,
  devis            jsonb not null default '{}'::jsonb,
  statut           text not null default 'ENVOYEE'
                   check (statut in ('ENVOYE','ENVOYEE','ANNULEE','ATTACHEE')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index if not exists sos_interventions_client_idx
  on sos_interventions (client_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 8. RPC : liste des pannes compatibles (filtrage dynamique strict)
-- ---------------------------------------------------------------------------
create or replace function sos_pannes_pour_vehicule(p_vehicule text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $func$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'code',             p.code,
        'libelle',          p.libelle,
        'description',      p.description,
        'main_oeuvre_fcfa', p.main_oeuvre_fcfa,
        'piece_obligatoire',p.piece_obligatoire,
        'piece_code',       p.piece_code,
        'piece_libelle',    p.piece_libelle
      ) order by p.position
    ) filter (where p.code is not null),
    '[]'::jsonb)
  from sos_pannes p
  join sos_panne_vehicules pv on pv.panne_code = p.code
  where pv.vehicule_code = upper(btrim(p_vehicule));
$func$;

-- ---------------------------------------------------------------------------
-- 9. RPC : matching prestataires + devis transparent
--    Règle clé (spéc §3) : un prestataire n'est retourné que si
--      (1) disponible + dossier approuvé        (équivalent status = 'ONLINE')
--      (2) au moins une compétence VALIDÉE de la panne
--      (3) vehicle_categories couvre le code véhicule ET habilitations
--          requises présentes
--      (4) pièce obligatoire en stock dans son catalogue
--    et distance <= min(rayon demandé, rayon_max_km du prestataire).
-- ---------------------------------------------------------------------------
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
  select true into v_existe
  from sos_pannes p
  join sos_panne_vehicules pv on pv.panne_code = p.code
  where p.code = v_panne and pv.vehicule_code = v_vehicule
  limit 1;

  if v_existe is null then
    raise exception 'PANNE_INCOMPATIBLE : la panne % n''est pas autorisée pour le véhicule %',
      v_panne, v_vehicule;
  end if;

  select sp.piece_code, sp.piece_obligatoire into v_piece_code, v_piece_obl
  from sos_pannes sp where sp.code = v_panne;

  select coalesce(array_agg(distinct c.skill_code), '{}') into v_comp
  from sos_panne_competences c where c.panne_code = v_panne;

  select coalesce(array_agg(distinct h), '{}') into v_hab
  from (
    select unnest(s.habilitations) as h
    from sos_panne_services ps
    join sos_services s on s.code = ps.service_code
    where ps.panne_code = v_panne
  ) hab;

  select coalesce(array_agg(distinct ps.service_code), '{}') into v_services
  from sos_panne_services ps where ps.panne_code = v_panne;

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
        'main_oeuvre_fcfa',   t.mo_fcfa,
        'piece_code',         v_piece_code,
        'piece_libelle',      t.piece_libelle,
        'piece_prix_fcfa',    t.piece_prix,
        'piece_stock',        t.piece_stock,
        'deplacement_fcfa',   t.deplacement_fcfa,
        'total_fcfa',         t.total_fcfa,
        'tarif_km_garanti',   t.tarif_km_fcfa
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
        ceil(p.tarif_km_fcfa * least(
            haversine_km(p.latitude, p.longitude, p_lat, p_lng),
            p.rayon_max_km::numeric
          ) / 50.0)::int * 50
      )::int as deplacement_fcfa,
      (
        pn.main_oeuvre_fcfa
        + coalesce(piece.prix_fcfa, 0)
        + greatest(
            p.frais_deplacement_min_fcfa,
            ceil(p.tarif_km_fcfa * least(
            haversine_km(p.latitude, p.longitude, p_lat, p_lng),
            p.rayon_max_km::numeric
          ) / 50.0)::int * 50
          )::int
      ) as total_fcfa,
      (select array_agg(distinct s.skill_code)
         from provider_skill_codes s
        where s.provider_id = p.id
          and s.valide
          and s.skill_code = any (v_comp)) as competences
    from providers p
    join sos_pannes pn on pn.code = v_panne
    left join public.profiles prof on prof.id = p.id
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
      and haversine_km(p.latitude, p.longitude, p_lat, p_lng) <= least(p_rayon_km, p.rayon_max_km::numeric)
    order by
      haversine_km(p.latitude, p.longitude, p_lat, p_lng) asc
    limit greatest(1, least(coalesce(p_limit, 5), 20))
  ) t;
$func$;

-- ---------------------------------------------------------------------------
-- 10. RPC : commande de l'intervention (devis recalculé et figé côté serveur)
-- ---------------------------------------------------------------------------
create or replace function sos_demander_intervention(
  p_vehicule       text,
  p_panne          text,
  p_lat            double precision,
  p_lng            double precision,
  p_prestataire    uuid,
  p_niveau_securite text default null,
  p_repere_local   text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $func$
declare
  v_client     uuid := auth.uid();
  v_vehicule   text := upper(btrim(p_vehicule));
  v_panne      text := upper(btrim(p_panne));
  v_match      jsonb;
  v_devis      jsonb;
  v_id         uuid;
begin
  if v_client is null then
    raise exception 'NON_CONNECTE';
  end if;

  v_match := sos_match_providers(
    p_vehicule => v_vehicule,
    p_panne    => v_panne,
    p_lat      => p_lat,
    p_lng      => p_lng,
    p_rayon_km => 15,
    p_limit    => 20
  );

  if not exists (
    select 1 from jsonb_array_elements(v_match) j
    where (j ->> 'id')::uuid = p_prestataire
  ) then
    raise exception 'PRESTATAIRE_INCOMPATIBLE : ce dépanneur ne couvre pas votre panne.';
  end if;

  v_devis := (
    select j -> 'devis' from jsonb_array_elements(v_match) j
    where (j ->> 'id')::uuid = p_prestataire
    limit 1
  );

  insert into sos_interventions (
    client_id, prestataire_id, vehicule_code, panne_code,
    niveau_securite, gps_lat, gps_lng, repere_local, devis, statut
  ) values (
    v_client, p_prestataire, v_vehicule, v_panne,
    upper(btrim(p_niveau_securite)), p_lat, p_lng, p_repere_local,
    v_devis, 'ENVOYE'
  )
  returning id into v_id;

  return v_id;
end;
$func$;

-- ---------------------------------------------------------------------------
-- 11. RLS + droits
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
alter table sos_interventions      enable row level security;
alter table provider_skill_codes   enable row level security;

drop policy if exists sos_niveaux_lecture        on sos_niveaux_securite;
drop policy if exists sos_vehicules_lecture       on sos_vehicules;
drop policy if exists sos_habilitations_lecture   on sos_habilitations;
drop policy if exists sos_competences_lecture     on sos_competences;
drop policy if exists sos_services_lecture        on sos_services;
drop policy if exists sos_pannes_lecture          on sos_pannes;
drop policy if exists sos_panne_vehicules_lecture on sos_panne_vehicules;
drop policy if exists sos_panne_comp_lecture      on sos_panne_competences;
drop policy if exists sos_panne_services_lecture  on sos_panne_services;

create policy sos_niveaux_lecture        on sos_niveaux_securite for select using (true);
create policy sos_vehicules_lecture      on sos_vehicules for select using (true);
create policy sos_habilitations_lecture  on sos_habilitations for select using (true);
create policy sos_competences_lecture    on sos_competences for select using (true);
create policy sos_services_lecture       on sos_services for select using (true);
create policy sos_pannes_lecture         on sos_pannes for select using (true);
create policy sos_panne_vehicules_lecture on sos_panne_vehicules for select using (true);
create policy sos_panne_comp_lecture     on sos_panne_competences for select using (true);
create policy sos_panne_services_lecture on sos_panne_services for select using (true);

drop policy if exists sos_interventions_proprietaire    on sos_interventions;
drop policy if exists sos_interventions_lecture         on sos_interventions;
drop policy if exists sos_interventions_prestataire     on sos_interventions;

create policy sos_interventions_proprietaire on sos_interventions
  for insert to authenticated
  with check (client_id = auth.uid());

create policy sos_interventions_lecture on sos_interventions
  for select to authenticated
  using (client_id = auth.uid());

create policy sos_interventions_prestataire on sos_interventions
  for select to authenticated
  using (prestataire_id = auth.uid());

drop policy if exists provider_skill_codes_proprio on provider_skill_codes;
drop policy if exists provider_skill_codes_admin   on provider_skill_codes;
drop policy if exists provider_skill_codes_public  on provider_skill_codes;

create policy provider_skill_codes_proprio on provider_skill_codes
  for all to authenticated
  using (provider_id = auth.uid())
  with check (provider_id = auth.uid());

create policy provider_skill_codes_admin on provider_skill_codes
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy provider_skill_codes_public on provider_skill_codes
  for select to anon
  using (valide is true);

grant execute on function sos_pannes_pour_vehicule(text) to anon, authenticated;
grant execute on function sos_match_providers(text, text, double precision, double precision, numeric, int)
  to anon, authenticated;
grant execute on function sos_demander_intervention(text, text, double precision, double precision, uuid, text, text)
  to authenticated;

commit;