-- ============================================================================
-- MonTotem — SOS PANNE : Script 03/10
-- Référentiel des pannes (18 pannes) + les 3 matrices de routage :
--   panne ↔ véhicule     (filtrage dynamique strict de l'Étape 3),
--   panne ↔ compétences  (required_skill_code validé),
--   panne ↔ services     (service de prestation express).
--
-- Exécution : après les scripts 01 et 02. Non destructif, idempotent.
-- Prérequis : 01, 02.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Référentiel des pannes
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
  -- Moto / Scooter / Tricycle Thermique
  ('CREVAISON_PNEU',          'Crevaison / Pneu / Chambre à air',
   'Tubeless ou chambre à air d''origine.', 2000, true,
   'CHAMBRE_AIR_MOTO', 'Chambre à air / pneu moto', 10),
  ('DEMARRAGE_BATTERIE',      'Panne de démarrage / Batterie / Bougie / Allumage',
   'Diagnostic allumage et charge.', 3000, false,
   'BOUGIE_MOTO', 'Bougie / batterie 12V moto', 20),
  ('TRANSMISSION_CABLE',      'Câble d''embrayage, frein, chaîne ou courroie cassée',
   'Remplacement à l''arrêt.', 3000, false,
   'CABLE_FREIN_MOTO', 'Câble / chaîne / courroie', 30),
  ('SURCHAUFFE_CALAGE',       'Surchauffe ou calage moteur',
   'Diagnostic thermique et redémarrage.', 3000, false,
   null, null, 40),
  -- Moto / Scooter / Voiture Électrique
  ('BATTERIE_VIDE',           'Batterie déchargée / Perte d''autonomie sur la route',
   'Swap ou recharge d''appoint.', 2500, false,
   'BATTERIE_ELEC', 'Batterie / faisceau swap', 50),
  ('BMS_CONTROLEUR',          'Alerte BMS / Contrôleur / Coupure de puissance',
   'Diagnostic électronique habilité.', 4000, false,
   null, null, 60),
  ('CREVAISON_ROUE_BLOQUEE',  'Crevaison / Roue bloquée',
   'Pneu tubeless ou roue greffée.', 3000, true,
   'CHAMBRE_AIR_MOTO', 'Chambre à air / pneu', 70),
  ('REMORQUAGE_PLATEAU',      'Remorquage plateau (immobilisation complète)',
   'Plateau VL vers l''atelier le plus proche.', 5000, false,
   null, null, 80),
  -- Voiture / Utilitaire / Minibus / Bus
  ('BATTERIE_ALTERNATEUR',    'Batterie à plat / Alternateur / Démarreur',
   'Boost ou remplacement.', 4000, false,
   'BATTERIE_VL', 'Batterie 12V véhicule léger', 90),
  ('CREVAISON_VL',            'Crevaison / Éclatement de pneu / Roue de secours absente',
   'Roue de secours ou réparation tubeless.', 3000, false,
   'PNEU_VL', 'Pneu véhicule léger', 100),
  ('SURCHAUFFE_FUITE',        'Surchauffe moteur / Fuite liquide de refroidissement ou huile',
   'Diagnostic et colmatage / durite.', 4500, false,
   null, null, 110),
  ('FREIN_EMBRAYAGE_COURROIE','Problème freinage, embrayage ou courroie',
   'Remplacement/pièce selon usure.', 4500, false,
   'COURROIE_VL', 'Courroie / plaquettes', 120),
  ('REMORQUAGE_VL',           'Véhicule immobilisé → Dépanneuse / Remorquage',
   'Dépanneuse VL, tarif au km garanti.', 5000, false,
   null, null, 130),
  -- Poids Lourds & Camions
  ('PNEU_PL',                 'Pneumatique Poids Lourd : Crevaison / Éclatement pneu jumelé ou essieu',
   'Nécessite cric hydraulique lourd / clé à chocs PL.', 12000, false,
   'VALVE_PL', 'Valve / chambre à air / pneu PL', 140),
  ('FREIN_AIR_PL',            'Circuit d''air & Freinage pneumatique : Chute de pression d''air, fuite flexible, frein de parc bloqué',
   'Intervention sur circuit d''air.', 15000, false,
   'FLEXIBLE_AIR_PL', 'Flexible / valve circuit d''air PL', 150),
  ('ENERGIE_24V',             'Énergie & Démarrage 24V : Batteries 24V à plat (couplage double batterie), alternateur ou démarreur lourd',
   'Couplage double batterie / alternateur.', 12000, false,
   'BATTERIE_24V', 'Batterie 24V PL', 160),
  ('MECA_LOURDE_PL',          'Mécanique lourde & Transmission : Surchauffe moteur / durite éclatée, casse arbre de transmission, embrayage ou boîte de vitesses',
   'Diagnostic PL + intervention.', 20000, false,
   null, null, 170),
  ('REMORQUAGE_PL',           'Immobilisation totale : Remorquage Poids Lourd (dépanneuse lourd tonnage / bras de levage)',
   'Prise en charge lourd tonnage, tarif au km garanti.', 25000, false,
   null, null, 180)
on conflict (code) do update
  set libelle           = excluded.libelle,
      description       = excluded.description,
      main_oeuvre_fcfa  = excluded.main_oeuvre_fcfa,
      piece_obligatoire = excluded.piece_obligatoire,
      piece_code        = excluded.piece_code,
      piece_libelle     = excluded.piece_libelle,
      position          = excluded.position;

-- ---------------------------------------------------------------------------
-- 2. Matrice panne ↔ véhicule (63 paires — exacte selon la spécification)
-- ---------------------------------------------------------------------------
create table if not exists sos_panne_vehicules (
  panne_code    text not null references sos_pannes (code)    on delete cascade,
  vehicule_code text not null references sos_vehicules (code) on delete cascade,
  primary key (panne_code, vehicule_code)
);

insert into sos_panne_vehicules (panne_code, vehicule_code)
select pn.panne_code, g.vehicule_code
from (values
  -- Moto / Scooter / Tricycle Thermique
  ('ZEM_MOTO',       array['CREVAISON_PNEU','DEMARRAGE_BATTERIE','TRANSMISSION_CABLE','SURCHAUFFE_CALAGE']),
  ('SCOOTER_THERM',  array['CREVAISON_PNEU','DEMARRAGE_BATTERIE','TRANSMISSION_CABLE','SURCHAUFFE_CALAGE']),
  ('CLOBOTO_PAX',    array['CREVAISON_PNEU','DEMARRAGE_BATTERIE','TRANSMISSION_CABLE','SURCHAUFFE_CALAGE']),
  ('KLOBOTO_FRET',   array['CREVAISON_PNEU','DEMARRAGE_BATTERIE','TRANSMISSION_CABLE','SURCHAUFFE_CALAGE']),
  -- Moto / Scooter / Voiture Électrique
  ('E_MOTO',         array['BATTERIE_VIDE','BMS_CONTROLEUR','CREVAISON_ROUE_BLOQUEE','REMORQUAGE_PLATEAU']),
  ('E_SCOOTER',      array['BATTERIE_VIDE','BMS_CONTROLEUR','CREVAISON_ROUE_BLOQUEE','REMORQUAGE_PLATEAU']),
  ('E_CAR',          array['BATTERIE_VIDE','BMS_CONTROLEUR','CREVAISON_ROUE_BLOQUEE','REMORQUAGE_PLATEAU']),
  -- Voiture / Utilitaire / Minibus / Bus
  ('CAR_THERM',      array['BATTERIE_ALTERNATEUR','CREVAISON_VL','SURCHAUFFE_FUITE','FREIN_EMBRAYAGE_COURROIE','REMORQUAGE_VL']),
  ('UTILITAIRE_VAN', array['BATTERIE_ALTERNATEUR','CREVAISON_VL','SURCHAUFFE_FUITE','FREIN_EMBRAYAGE_COURROIE','REMORQUAGE_VL']),
  ('MINIBUS',        array['BATTERIE_ALTERNATEUR','CREVAISON_VL','SURCHAUFFE_FUITE','FREIN_EMBRAYAGE_COURROIE','REMORQUAGE_VL']),
  ('BUS_TRANSPORT',  array['BATTERIE_ALTERNATEUR','CREVAISON_VL','SURCHAUFFE_FUITE','FREIN_EMBRAYAGE_COURROIE','REMORQUAGE_VL']),
  -- Poids Lourds & Camions
  ('CAMION_6_ROUES', array['PNEU_PL','FREIN_AIR_PL','ENERGIE_24V','MECA_LOURDE_PL','REMORQUAGE_PL']),
  ('CAMION_10_ROUES',array['PNEU_PL','FREIN_AIR_PL','ENERGIE_24V','MECA_LOURDE_PL','REMORQUAGE_PL']),
  ('SEMI_REMORQUE',  array['PNEU_PL','FREIN_AIR_PL','ENERGIE_24V','MECA_LOURDE_PL','REMORQUAGE_PL'])
) as g(vehicule_code, pannes)
cross join lateral unnest(g.pannes) as pn(panne_code)
join sos_vehicules v on v.code = g.vehicule_code
on conflict (panne_code, vehicule_code) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Matrice panne ↔ compétences (required_skill_code)
-- ---------------------------------------------------------------------------
create table if not exists sos_panne_competences (
  panne_code text not null references sos_pannes (code)      on delete cascade,
  skill_code text not null references sos_competences (code)  on delete cascade,
  primary key (panne_code, skill_code)
);

insert into sos_panne_competences (panne_code, skill_code) values
  ('CREVAISON_PNEU',          'PNEU_MOTO'),
  ('CREVAISON_PNEU',          'PNEU_VL'),
  ('DEMARRAGE_BATTERIE',      'ELEC_AUTO'),
  ('DEMARRAGE_BATTERIE',      'MECANIQUE_MOTO'),
  ('TRANSMISSION_CABLE',      'MECANIQUE_MOTO'),
  ('SURCHAUFFE_CALAGE',       'MECANIQUE_MOTO'),
  ('BATTERIE_VIDE',           'ELEC_VEHICULE_HAB'),
  ('BATTERIE_VIDE',           'SWAP_BATTERIE'),
  ('BMS_CONTROLEUR',          'ELEC_VEHICULE_HAB'),
  ('BMS_CONTROLEUR',          'SWAP_BATTERIE'),
  ('CREVAISON_ROUE_BLOQUEE',  'PNEU_MOTO'),
  ('CREVAISON_ROUE_BLOQUEE',  'PNEU_VL'),
  ('REMORQUAGE_PLATEAU',      'REMORQUAGE_VL'),
  ('BATTERIE_ALTERNATEUR',    'ELEC_AUTO'),
  ('BATTERIE_ALTERNATEUR',    'MECANIQUE_VL'),
  ('CREVAISON_VL',            'PNEU_VL'),
  ('SURCHAUFFE_FUITE',        'MECANIQUE_VL'),
  ('FREIN_EMBRAYAGE_COURROIE','MECANIQUE_VL'),
  ('REMORQUAGE_VL',           'REMORQUAGE_VL'),
  ('PNEU_PL',                 'PNEU_PL'),
  ('FREIN_AIR_PL',            'FREIN_AIR_PL'),
  ('ENERGIE_24V',             'DIAG_24V_PL'),
  ('MECA_LOURDE_PL',          'MECA_LOURDE_PL'),
  ('REMORQUAGE_PL',           'REMORQUAGE_PL')
on conflict (panne_code, skill_code) do nothing;

-- ---------------------------------------------------------------------------
-- 4. Matrice panne ↔ services de prestation express
-- ---------------------------------------------------------------------------
create table if not exists sos_panne_services (
  panne_code   text not null references sos_pannes (code)   on delete cascade,
  service_code text not null references sos_services (code) on delete cascade,
  primary key (panne_code, service_code)
);

insert into sos_panne_services (panne_code, service_code) values
  ('CREVAISON_PNEU',          'VULCANISATEUR_EXPRESS'),
  ('DEMARRAGE_BATTERIE',      'ATELIER_MOBILE_LEGER'),
  ('TRANSMISSION_CABLE',      'ATELIER_MOBILE_LEGER'),
  ('SURCHAUFFE_CALAGE',       'ATELIER_MOBILE_LEGER'),
  ('BATTERIE_VIDE',           'TECH_ELECTRIQUE'),
  ('BMS_CONTROLEUR',          'TECH_ELECTRIQUE'),
  ('BMS_CONTROLEUR',          'DEPANNEUSE_VL'),
  ('CREVAISON_ROUE_BLOQUEE',  'VULCANISATEUR_EXPRESS'),
  ('REMORQUAGE_PLATEAU',      'DEPANNEUSE_VL'),
  ('BATTERIE_ALTERNATEUR',    'ATELIER_MOBILE_LEGER'),
  ('BATTERIE_ALTERNATEUR',    'GARAGE_MECANIQUE'),
  ('CREVAISON_VL',            'VULCANISATEUR_EXPRESS'),
  ('SURCHAUFFE_FUITE',        'ATELIER_MOBILE_LEGER'),
  ('SURCHAUFFE_FUITE',        'GARAGE_MECANIQUE'),
  ('FREIN_EMBRAYAGE_COURROIE','ATELIER_MOBILE_LEGER'),
  ('FREIN_EMBRAYAGE_COURROIE','GARAGE_MECANIQUE'),
  ('REMORQUAGE_VL',           'DEPANNEUSE_VL'),
  ('PNEU_PL',                 'VULCANISATEUR_PL'),
  ('FREIN_AIR_PL',            'CAMION_ATELIER_PL'),
  ('ENERGIE_24V',             'CAMION_ATELIER_PL'),
  ('MECA_LOURDE_PL',          'CAMION_ATELIER_PL'),
  ('MECA_LOURDE_PL',          'DEPANNEUSE_PL'),
  ('REMORQUAGE_PL',           'DEPANNEUSE_PL')
on conflict (panne_code, service_code) do nothing;

commit;