-- ============================================================================
-- MonTotem — F-23 : MÉCANIQUE COMPLÈTE — PANNES D'EXPERTS + MÉTIERS
-- SPÉCIALISTES
-- ============================================================================
-- Audit du monde de la mécanique (routes africaines) : ce qui manquait au
-- référentiel SOS après F-21/F-22, et qui est ajouté ici :
--
--   1. CINQ nouvelles compétences de spécialistes :
--        SOUDURE_CHASSIS    soudeur métallier (châssis fissurés, bennes)
--        DIAG_ELECTRONIQUE  mécatronicien (valise OBD2, calculateurs ECU)
--        INJECTION_DIESEL   diéséliste (pompes et injecteurs haute pression)
--        HYDRAULIQUE_PL     hydraulicien PL (vérins de benne, hayons)
--        CARROSSERIE_TOLE   tôlier-peintre (redressage, peinture)
--
--   2. DIX nouvelles pannes quotidiennes :
--        2/3-roues : EMBRAYAGE_PATINE, PONT_DIFFERENTIEL, CARBURATEUR_BOUGIE,
--                    REGULATEUR_CHARGE, SERRAGE_MOTEUR
--        VL        : VOYANT_MOTEUR_CAPTEUR, INJECTION_DIESEL, TRAIN_ROULANT_VL
--        PL        : SUSPENSION_PL, HYDRAULIQUE_PL
--
--   3. Les trois matrices complétées (véhicule, compétences, services).
--
--   4. CINQ nouveaux métiers pro reconnus à l'inscription :
--        'Soudeur / Châssis', 'Mécatronicien (diagnostic auto)',
--        'Diéséliste (injection)', 'Tôlier-Peintre', 'Hydraulicien PL'
--      + dérivation automatique de leurs compétences SOS
--      + rattrapage des pros déjà inscrits.
--
-- Prérequis : scripts sos 01..03, F-21, F-22. Non destructif, idempotent.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Compétences de spécialistes
-- ---------------------------------------------------------------------------
insert into sos_competences (code, libelle) values
  ('SOUDURE_CHASSIS',   'Soudeur / réparation châssis & benne (tricycles)'),
  ('DIAG_ELECTRONIQUE', 'Mécatronicien : diagnostic électronique OBD2 / ECU'),
  ('INJECTION_DIESEL',  'Diéséliste : pompes & injecteurs haute pression'),
  ('HYDRAULIQUE_PL',    'Hydraulicien PL : vérins, flexibles, bennes, hayons'),
  ('CARROSSERIE_TOLE',  'Tôlier-peintre : carrosserie & peinture')
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Dix nouvelles pannes
-- ---------------------------------------------------------------------------
insert into sos_pannes (code, libelle, description, main_oeuvre_fcfa,
                        piece_obligatoire, piece_code, piece_libelle,
                        position) values
  ('EMBRAYAGE_PATINE',
   'Embrayage qui patine (tricycle surchargé)',
   'Le moteur monte dans les tours mais le tricycle n''avance plus.',
   4000, false, 'DISQUE_EMBRAYAGE', 'Disque d''embrayage / garnitures', 53),
  ('PONT_DIFFERENTIEL',
   'Pont / différentiel arrière bruyant ou bloqué (tricycle)',
   'Claquements à l''accélération, roue arrière qui se bloque.',
   5000, false, 'HUILE_PONT', 'Huile de pont / joint spi', 54),
  ('CARBURATEUR_BOUGIE',
   'Carburateur encrassé / bougie noyée / filtre à air bouché',
   'Démarrages difficiles, moteur qui cale, gros ralenti instable.',
   3000, false, 'KIT_CARBURATION', 'Kit carburation (bougie, filtre, joints)', 55),
  ('REGULATEUR_CHARGE',
   'Batterie qui ne charge plus / régulateur grillé',
   'Phares faibles, batterie morte en répétition malgré un remplacement.',
   3500, false, 'REGULATEUR_TENSION', 'Régulateur de tension / redresseur', 56),
  ('SERRAGE_MOTEUR',
   'Serrage moteur / fumée bleue ou blanche (haut moteur)',
   'Manque d''huile ou surchauffe : segments usés, perte de puissance.',
   10000, false, 'REVISION_HAUT_MOTEUR', 'Segments, joints, huile moteur', 57),
  ('VOYANT_MOTEUR_CAPTEUR',
   'Voyant moteur allumé / capteur défaillant (diagnostic électronique)',
   'Diagnostic valise OBD2 : capteurs PMH, débitmètre, sonde lambda.',
   3500, false, null, null, 58),
  ('INJECTION_DIESEL',
   'Pompe ou injecteurs diesel grippés (Common Rail)',
   'Pertes de puissance, fumée noire, démarrage diesel difficile.',
   7000, false, 'FILTRE_GASOIL', 'Filtre à gasoil / injecteur', 59),
  ('TRAIN_ROULANT_VL',
   'Rotules, silentblocs, cardans ou roulements (claquements)',
   'Jeux dans la direction, claquements sur routes dégradées.',
   6000, false, 'ROTULE_SILENTBLOC', 'Rotule / silentbloc / roulement', 60),
  ('SUSPENSION_PL',
   'Lames de ressort, coussins d''air, balanciers (Poids Lourd)',
   'Caisse qui penche, lames cassées par surcharge, chocs répétés.',
   8000, false, 'LAME_RESSORT', 'Lame de ressort / boudin d''air', 61),
  ('HYDRAULIQUE_PL',
   'Vérin de benne, hayon ou flexible hydraulique HS',
   'Benne qui ne se lève plus, fuite d''huile hydraulique.',
   9000, false, 'FLEXIBLE_HYDRAULIQUE', 'Flexible / pompe hydraulique', 62)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Matrice panne ↔ véhicule
-- ---------------------------------------------------------------------------
insert into sos_panne_vehicules (panne_code, vehicule_code)
select pn.panne_code, g.vehicule_code
from (values
  ('EMBRAYAGE_PATINE',     array['ZEM_MOTO','SCOOTER_THERM','CLOBOTO_PAX','KLOBOTO_FRET']),
  ('PONT_DIFFERENTIEL',    array['CLOBOTO_PAX','KLOBOTO_FRET']),
  ('CARBURATEUR_BOUGIE',   array['ZEM_MOTO','SCOOTER_THERM','CLOBOTO_PAX','KLOBOTO_FRET']),
  ('REGULATEUR_CHARGE',    array['ZEM_MOTO','SCOOTER_THERM','CLOBOTO_PAX','KLOBOTO_FRET']),
  ('SERRAGE_MOTEUR',       array['ZEM_MOTO','SCOOTER_THERM','CLOBOTO_PAX','KLOBOTO_FRET']),
  ('VOYANT_MOTEUR_CAPTEUR',array['CAR_THERM','E_CAR','UTILITAIRE_VAN','MINIBUS','BUS_TRANSPORT']),
  ('INJECTION_DIESEL',     array['CAR_THERM','UTILITAIRE_VAN','MINIBUS','BUS_TRANSPORT',
                                 'CAMION_6_ROUES','CAMION_10_ROUES','SEMI_REMORQUE']),
  ('TRAIN_ROULANT_VL',     array['CAR_THERM','E_CAR','UTILITAIRE_VAN','MINIBUS','BUS_TRANSPORT']),
  ('SUSPENSION_PL',        array['CAMION_6_ROUES','CAMION_10_ROUES','SEMI_REMORQUE']),
  ('HYDRAULIQUE_PL',       array['CAMION_10_ROUES','SEMI_REMORQUE'])
) as g(panne_code, vehicules)
cross join lateral unnest(g.vehicules) as vt(vehicule_code)
join sos_vehicules v on v.code = vt.vehicule_code
on conflict (panne_code, vehicule_code) do nothing;

-- ---------------------------------------------------------------------------
-- 4. Matrice panne ↔ compétences
-- ---------------------------------------------------------------------------
insert into sos_panne_competences (panne_code, skill_code) values
  ('EMBRAYAGE_PATINE',      'MECANIQUE_MOTO'),
  ('EMBRAYAGE_PATINE',      'SOUDURE_CHASSIS'),
  ('PONT_DIFFERENTIEL',     'MECANIQUE_MOTO'),
  ('CARBURATEUR_BOUGIE',    'MECANIQUE_MOTO'),
  ('REGULATEUR_CHARGE',     'ELEC_AUTO'),
  ('SERRAGE_MOTEUR',        'MECANIQUE_MOTO'),
  ('VOYANT_MOTEUR_CAPTEUR', 'DIAG_ELECTRONIQUE'),
  ('VOYANT_MOTEUR_CAPTEUR', 'ELEC_AUTO'),
  ('INJECTION_DIESEL',      'INJECTION_DIESEL'),
  ('INJECTION_DIESEL',      'MECANIQUE_VL'),
  ('INJECTION_DIESEL',      'MECA_LOURDE_PL'),
  ('TRAIN_ROULANT_VL',      'MECANIQUE_VL'),
  ('TRAIN_ROULANT_VL',      'PNEU_VL'),
  ('SUSPENSION_PL',         'MECA_LOURDE_PL'),
  ('SUSPENSION_PL',         'PNEU_PL'),
  ('HYDRAULIQUE_PL',        'HYDRAULIQUE_PL'),
  ('HYDRAULIQUE_PL',        'MECA_LOURDE_PL'),
  -- Les pannes déjà connues gagnent le soudeur côté tricycles :
  ('TRANSMISSION_CABLE',    'SOUDURE_CHASSIS'),
  ('SURCHAUFFE_CALAGE',     'SOUDURE_CHASSIS'),
  ('SUSPENSION_AMORTISSEUR','SOUDURE_CHASSIS')
on conflict (panne_code, skill_code) do nothing;

-- ---------------------------------------------------------------------------
-- 5. Matrice panne ↔ services
-- ---------------------------------------------------------------------------
insert into sos_panne_services (panne_code, service_code) values
  ('EMBRAYAGE_PATINE',      'ATELIER_MOBILE_LEGER'),
  ('EMBRAYAGE_PATINE',      'GARAGE_MECANIQUE'),
  ('PONT_DIFFERENTIEL',     'ATELIER_MOBILE_LEGER'),
  ('PONT_DIFFERENTIEL',     'GARAGE_MECANIQUE'),
  ('CARBURATEUR_BOUGIE',    'ATELIER_MOBILE_LEGER'),
  ('REGULATEUR_CHARGE',     'ATELIER_MOBILE_LEGER'),
  ('REGULATEUR_CHARGE',     'TECH_ELECTRIQUE'),
  ('SERRAGE_MOTEUR',        'ATELIER_MOBILE_LEGER'),
  ('SERRAGE_MOTEUR',        'GARAGE_MECANIQUE'),
  ('VOYANT_MOTEUR_CAPTEUR', 'ATELIER_MOBILE_LEGER'),
  ('VOYANT_MOTEUR_CAPTEUR', 'GARAGE_MECANIQUE'),
  ('INJECTION_DIESEL',      'ATELIER_MOBILE_LEGER'),
  ('INJECTION_DIESEL',      'GARAGE_MECANIQUE'),
  ('INJECTION_DIESEL',      'CAMION_ATELIER_PL'),
  ('TRAIN_ROULANT_VL',      'ATELIER_MOBILE_LEGER'),
  ('TRAIN_ROULANT_VL',      'GARAGE_MECANIQUE'),
  ('SUSPENSION_PL',         'CAMION_ATELIER_PL'),
  ('SUSPENSION_PL',         'GARAGE_MECANIQUE'),
  ('HYDRAULIQUE_PL',        'CAMION_ATELIER_PL')
on conflict (panne_code, service_code) do nothing;

-- ---------------------------------------------------------------------------
-- 6. Nouveaux métiers reconnus (trigger des libellés verrouillés)
--    Les spécialistes reprennent la famille mécanique : le libellé exact
--    reste stocké dans providers.metier et pilote les compétences SOS.
-- ---------------------------------------------------------------------------
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
    when lower(coalesce(p_metier, '')) like '%garage%'
      or lower(coalesce(p_metier, '')) like '%diéséliste%'
      or lower(coalesce(p_metier, '')) like '%dieseliste%'
      or lower(coalesce(p_metier, '')) like '%mécatronicien%'
      or lower(coalesce(p_metier, '')) like '%mecatronicien%'
      or lower(coalesce(p_metier, '')) like '%hydraulicien%'
      or lower(coalesce(p_metier, '')) like '%soud%'
      or lower(coalesce(p_metier, '')) like '%tôlier%'
      or lower(coalesce(p_metier, '')) like '%tolier%'        then 'garage'
    else 'mecanicien'
  end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Dérivation SOS des CINQ nouveaux métiers (même logique que F-22)
-- ---------------------------------------------------------------------------
create or replace function public.sync_provider_sos_profile(p_provider uuid)
returns void
language plpgsql
security definer
set search_path = public
as $func$
declare
  v_metier text;
  v_services text[] := '{}';
  v_hab      text[] := '{}';
begin
  select metier, vehicle_types into v_metier
  from providers where id = p_provider;
  if v_metier is null then return; end if;

  -- Catégories de véhicules SOS déduites des types de véhicules.
  update providers
     set vehicle_categories = sos_categories_from_types(vehicle_types)
   where id = p_provider;

  -- Services express, habilitations et compétences selon le métier.
  v_services := case v_metier
    when 'Mécanicien'               then array['ATELIER_MOBILE_LEGER','GARAGE_MECANIQUE']
    when 'Service garage'           then array['GARAGE_MECANIQUE']
    when 'Vulcanisateur pneu'       then array['VULCANISATEUR_EXPRESS']
    when 'Électricien auto & moto'  then array['ATELIER_MOBILE_LEGER','TECH_ELECTRIQUE']
    when 'Dépanneuse / Remorquage'  then array['DEPANNEUSE_VL','DEPANNEUSE_PL']
    when 'Vendeur de carburant'     then array['ATELIER_MOBILE_LEGER']
    when 'Soudeur / Châssis'        then array['ATELIER_MOBILE_LEGER','GARAGE_MECANIQUE']
    when 'Mécatronicien (diagnostic auto)'
                                    then array['ATELIER_MOBILE_LEGER','GARAGE_MECANIQUE']
    when 'Diéséliste (injection)'   then array['ATELIER_MOBILE_LEGER','GARAGE_MECANIQUE']
    when 'Tôlier-Peintre'           then array['GARAGE_MECANIQUE']
    when 'Hydraulicien PL'          then array['CAMION_ATELIER_PL','GARAGE_MECANIQUE']
    else '{}'::text[]
  end;
  v_hab := case v_metier
    when 'Électricien auto & moto' then array['HAB_ELECTRIQUE']
    when 'Mécatronicien (diagnostic auto)' then array['HAB_ELECTRIQUE']
    when 'Dépanneuse / Remorquage' then array['HAB_DEPANNEUSE_VL','HAB_DEPANNEUSE_PL']
    else '{}'::text[]
  end;

  update providers
     set sos_services  = v_services,
         habilitations = v_hab
   where id = p_provider;

  -- Compétences : en attente de validation admin (valide = false).
  insert into provider_skill_codes (provider_id, skill_code)
  select p_provider, s.skill_code
  from (values
    ('Mécanicien',              array['MECANIQUE_MOTO','MECANIQUE_VL']),
    ('Service garage',          array['MECANIQUE_MOTO','MECANIQUE_VL']),
    ('Vulcanisateur pneu',      array['PNEU_MOTO','PNEU_VL']),
    ('Électricien auto & moto', array['ELEC_AUTO','ELEC_VEHICULE_HAB','SWAP_BATTERIE']),
    ('Dépanneuse / Remorquage', array['REMORQUAGE_VL','REMORQUAGE_PL']),
    ('Vendeur de carburant',    array['LIVRAISON_CARBURANT']),
    ('Soudeur / Châssis',       array['SOUDURE_CHASSIS','MECANIQUE_MOTO']),
    ('Mécatronicien (diagnostic auto)',
                                array['DIAG_ELECTRONIQUE','ELEC_AUTO','ELEC_VEHICULE_HAB']),
    ('Diéséliste (injection)',  array['INJECTION_DIESEL','MECANIQUE_VL']),
    ('Tôlier-Peintre',          array['CARROSSERIE_TOLE']),
    ('Hydraulicien PL',         array['HYDRAULIQUE_PL','MECA_LOURDE_PL'])
  ) as m(metier, skills)
  cross join lateral unnest(m.skills) as s(skill_code)
  where m.metier = v_metier
  on conflict (provider_id, skill_code) do nothing;
end;
$func$;
revoke all on function public.sync_provider_sos_profile(uuid) from public, anon;
grant execute on function public.sync_provider_sos_profile(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Rattrapage : les pros existants des nouveaux métiers (s'ils existent
--    déjà en base) deviennent trouvables immédiatement.
-- ---------------------------------------------------------------------------
update providers p
   set vehicle_categories = sos_categories_from_types(p.vehicle_types),
       sos_services  = case p.metier
         when 'Soudeur / Châssis'        then array['ATELIER_MOBILE_LEGER','GARAGE_MECANIQUE']
         when 'Mécatronicien (diagnostic auto)'
                                         then array['ATELIER_MOBILE_LEGER','GARAGE_MECANIQUE']
         when 'Diéséliste (injection)'   then array['ATELIER_MOBILE_LEGER','GARAGE_MECANIQUE']
         when 'Tôlier-Peintre'           then array['GARAGE_MECANIQUE']
         when 'Hydraulicien PL'          then array['CAMION_ATELIER_PL','GARAGE_MECANIQUE']
         else '{}'::text[]
       end,
       habilitations = case p.metier
         when 'Mécatronicien (diagnostic auto)' then array['HAB_ELECTRIQUE']
         else '{}'::text[]
       end
 where p.metier in ('Soudeur / Châssis', 'Mécatronicien (diagnostic auto)',
                    'Diéséliste (injection)', 'Tôlier-Peintre', 'Hydraulicien PL');

insert into provider_skill_codes (provider_id, skill_code)
select p.id, s.skill_code
from providers p
join (values
  ('Soudeur / Châssis',       array['SOUDURE_CHASSIS','MECANIQUE_MOTO']),
  ('Mécatronicien (diagnostic auto)',
                              array['DIAG_ELECTRONIQUE','ELEC_AUTO','ELEC_VEHICULE_HAB']),
  ('Diéséliste (injection)',  array['INJECTION_DIESEL','MECANIQUE_VL']),
  ('Tôlier-Peintre',          array['CARROSSERIE_TOLE']),
  ('Hydraulicien PL',         array['HYDRAULIQUE_PL','MECA_LOURDE_PL'])
) as m(metier, skills) on m.metier = p.metier
cross join lateral unnest(m.skills) as s(skill_code)
on conflict (provider_id, skill_code) do nothing;

commit;

-- ── Contrôles (à exécuter après le script) ──
-- SELECT code, libelle FROM public.sos_competences ORDER BY code;          -- 19 attendues
-- SELECT code FROM public.sos_pannes ORDER BY position;                    -- 36 attendues
-- SELECT p.metier, p.sos_services FROM providers p
--  WHERE p.metier LIKE '%Soudeur%' OR p.metier LIKE '%Diéséliste%';
