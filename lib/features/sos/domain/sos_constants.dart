import 'package:flutter/material.dart';

/// Référentiel officiel du module « SOS Je Suis En Panne ».
///
/// Les codes ci-dessous sont la source unique côté client : ils doivent
/// rester strictement identiques à la migration SQL
/// `supabase/migrations/sos/01..03` (tables `sos_vehicules`, `sos_pannes`,
/// `sos_competences`, `sos_services`, `sos_habilitations`,
/// `sos_niveaux_securite`).

enum SosGroupe {
  deuxRoues('DEUX_ROUES', 'Deux-roues'),
  troisRoues('TROIS_ROUES', 'Trois-roues'),
  quatreRoues('QUATRE_ROUES', 'Voit. / Utilitaire / Minibus / Bus'),
  poidsLourd('POIDS_LOURD', 'Poids Lourds & Camions');

  const SosGroupe(this.code, this.libelle);
  final String code;
  final String libelle;

  static SosGroupe fromCode(String? c) => SosGroupe.values.firstWhere(
    (g) => g.code == c,
    orElse: () => SosGroupe.quatreRoues,
  );
}

@immutable
class SosVehicule {
  const SosVehicule({
    required this.code,
    required this.libelle,
    required this.detail,
    required this.groupe,
    required this.thermique,
    required this.icone,
  });

  /// Code exact stocké en base (sos_vehicules).
  final String code;
  final String libelle;
  final String detail;
  final SosGroupe groupe;
  final bool thermique;
  final IconData icone;
}

/// Les 14 véhicules de la spécification, dans l'ordre d'affichage.
const List<SosVehicule> kSosVehicules = [
  SosVehicule(
    code: 'ZEM_MOTO',
    libelle: 'Moto classique',
    detail: 'Motos et cyclomoteurs',
    groupe: SosGroupe.deuxRoues,
    thermique: true,
    icone: Icons.two_wheeler_rounded,
  ),
  SosVehicule(
    code: 'E_MOTO',
    libelle: 'Moto électrique',
    detail: 'Recharge / swap batterie',
    groupe: SosGroupe.deuxRoues,
    thermique: false,
    icone: Icons.electric_moped_rounded,
  ),
  SosVehicule(
    code: 'SCOOTER_THERM',
    libelle: 'Scooter mécanique',
    detail: 'Scooters thermiques',
    groupe: SosGroupe.deuxRoues,
    thermique: true,
    icone: Icons.two_wheeler_rounded,
  ),
  SosVehicule(
    code: 'E_SCOOTER',
    libelle: 'Scooter électrique',
    detail: 'Scooters électriques',
    groupe: SosGroupe.deuxRoues,
    thermique: false,
    icone: Icons.electric_scooter,
  ),
  SosVehicule(
    code: 'CLOBOTO_PAX',
    libelle: 'Tricycle passager',
    detail: 'Cloboto transport de personnes',
    groupe: SosGroupe.troisRoues,
    thermique: true,
    icone: Icons.electric_rickshaw_rounded,
  ),
  SosVehicule(
    code: 'KLOBOTO_FRET',
    libelle: 'Tricycle fret/bagage',
    detail: 'Kloboto transport de marchandises',
    groupe: SosGroupe.troisRoues,
    thermique: true,
    icone: Icons.inventory_2_rounded,
  ),
  SosVehicule(
    code: 'CAR_THERM',
    libelle: 'Voiture thermique',
    detail: 'Essence / diesel',
    groupe: SosGroupe.quatreRoues,
    thermique: true,
    icone: Icons.directions_car_rounded,
  ),
  SosVehicule(
    code: 'E_CAR',
    libelle: 'Voiture électrique/hybride',
    detail: 'BMS, contrôleur, charge',
    groupe: SosGroupe.quatreRoues,
    thermique: false,
    icone: Icons.electric_car_rounded,
  ),
  SosVehicule(
    code: 'UTILITAIRE_VAN',
    libelle: 'Utilitaire',
    detail: 'Vans, fourgons, utilitaires',
    groupe: SosGroupe.quatreRoues,
    thermique: true,
    icone: Icons.local_shipping_rounded,
  ),
  SosVehicule(
    code: 'MINIBUS',
    libelle: 'Minibus',
    detail: 'Transport collectif léger',
    groupe: SosGroupe.quatreRoues,
    thermique: true,
    icone: Icons.directions_bus_rounded,
  ),
  SosVehicule(
    code: 'BUS_TRANSPORT',
    libelle: 'Bus',
    detail: 'Transport collectif',
    groupe: SosGroupe.quatreRoues,
    thermique: true,
    icone: Icons.directions_bus_filled_rounded,
  ),
  SosVehicule(
    code: 'CAMION_6_ROUES',
    libelle: 'Camion léger / Porteur 6 roues',
    detail: 'Kia/Hyundai/Canter — tonnage moyen',
    groupe: SosGroupe.poidsLourd,
    thermique: true,
    icone: Icons.local_shipping_rounded,
  ),
  SosVehicule(
    code: 'CAMION_10_ROUES',
    libelle: 'Camion lourd 10 roues / Benne',
    detail: 'Tonnage lourd',
    groupe: SosGroupe.poidsLourd,
    thermique: true,
    icone: Icons.fire_truck_rounded,
  ),
  SosVehicule(
    code: 'SEMI_REMORQUE',
    libelle: 'Tracteur routier / Semi-remorque',
    detail: '12 roues et plus',
    groupe: SosGroupe.poidsLourd,
    thermique: true,
    icone: Icons.local_shipping_outlined,
  ),
];

SosVehicule? sosVehiculeParCode(String? code) {
  if (code == null) {
    return null;
  }
  final c = code.trim().toUpperCase();
  for (final v in kSosVehicules) {
    if (v.code == c) {
      return v;
    }
  }
  return null;
}

/// Niveau de sécurité de la chaussée (Étape 1).
enum SosNiveauSecurite {
  ok('OK', 'Route normale', Icons.check_circle_outline_rounded),
  attention(
    'ATTENTION',
    'Trafic proche / voie étroite',
    Icons.warning_amber_rounded,
  ),
  danger('DANGER', 'Voie rapide / zone dangereuse', Icons.dangerous_rounded);

  const SosNiveauSecurite(this.code, this.libelle, this.icone);
  final String code;
  final String libelle;
  final IconData icone;

  static SosNiveauSecurite fromCode(String? c) =>
      SosNiveauSecurite.values.firstWhere(
        (n) => n.code == c,
        orElse: () => SosNiveauSecurite.attention,
      );

  String get consigne => switch (this) {
    SosNiveauSecurite.ok => 'Garez-vous hors de la chaussée, triangle à 25 m.',
    SosNiveauSecurite.attention =>
      'Gilet puis triangle à 50 m. Restez derrière une barrière.',
    SosNiveauSecurite.danger =>
      'Ne restez pas dans le véhicule. Éloignez-vous.',
  };
}

@immutable
class SosPanne {
  const SosPanne({
    required this.code,
    required this.libelle,
    required this.description,
    required this.mainOeuvreFcfa,
    required this.pieceObligatoire,
    required this.icone,
    this.pieceCode,
    this.pieceLibelle,
  });

  final String code;
  final String libelle;
  final String description;

  /// Main-d'œuvre indicative de référence (le devis réel vient de la RPC).
  final int mainOeuvreFcfa;

  /// Si true, un prestataire sans la pièce en stock n'est jamais proposé.
  final bool pieceObligatoire;
  final String? pieceCode;
  final String? pieceLibelle;
  final IconData icone;

  factory SosPanne.fromJson(Map<String, dynamic> j) => SosPanne(
    code: '${j['code'] ?? ''}',
    libelle: '${j['libelle'] ?? ''}',
    description: '${j['description'] ?? ''}',
    mainOeuvreFcfa: (j['main_oeuvre_fcfa'] as num?)?.toInt() ?? 0,
    pieceObligatoire: j['piece_obligatoire'] == true,
    pieceCode: j['piece_code'] as String?,
    pieceLibelle: j['piece_libelle'] as String?,
    icone: iconePourPanne('${j['code'] ?? ''}'),
  );
}

IconData iconePourPanne(String code) => switch (code) {
  'CREVAISON_PNEU' => Icons.tire_repair_rounded,
  'DEMARRAGE_BATTERIE' => Icons.battery_alert_rounded,
  'TRANSMISSION_CABLE' => Icons.link_off_rounded,
  'SURCHAUFFE_CALAGE' => Icons.thermostat_rounded,
  'COURROIE_CASSEE' => Icons.settings_rounded,
  'CHAINE_CASSEE' => Icons.link_off_rounded,
  'CARBURANT_EPUISE' => Icons.local_gas_station_rounded,
  'FREIN_MOTO' => Icons.stop_circle_rounded,
  'ECLAIRAGE_CLAXON' => Icons.highlight_rounded,
  'FUITE_HUILE' => Icons.opacity_rounded,
  'ROUE_DEJANTEE' => Icons.album_rounded,
  'SUSPENSION_AMORTISSEUR' => Icons.compress_rounded,
  'BATTERIE_VIDE' => Icons.battery_alert_rounded,
  'BMS_CONTROLEUR' => Icons.developer_board_rounded,
  'CREVAISON_ROUE_BLOQUEE' => Icons.tire_repair_rounded,
  'REMORQUAGE_PLATEAU' => Icons.local_shipping_rounded,
  'BATTERIE_ALTERNATEUR' => Icons.battery_alert_rounded,
  'CREVAISON_VL' => Icons.tire_repair_rounded,
  'SURCHAUFFE_FUITE' => Icons.water_drop_rounded,
  'FREIN_EMBRAYAGE_COURROIE' => Icons.disc_full_rounded,
  'REMORQUAGE_VL' => Icons.local_shipping_rounded,
  'PNEU_PL' => Icons.tire_repair_rounded,
  'FREIN_AIR_PL' => Icons.air_rounded,
  'ENERGIE_24V' => Icons.battery_charging_full_rounded,
  'MECA_LOURDE_PL' => Icons.precision_manufacturing_rounded,
  'REMORQUAGE_PL' => Icons.local_shipping_rounded,
  _ => Icons.build_circle_rounded,
};

/// Matrice de filtrage strict (Étape 3) — codes exacts de la spécification.
const Map<String, List<String>> kSosPannesParVehicule = {
  // Moto / Scooter / Tricycle Thermique
  'ZEM_MOTO': [
    'CREVAISON_PNEU',
    'DEMARRAGE_BATTERIE',
    'CHAINE_CASSEE',
    'TRANSMISSION_CABLE',
    'SURCHAUFFE_CALAGE',
    'CARBURANT_EPUISE',
    'FREIN_MOTO',
    'ECLAIRAGE_CLAXON',
    'FUITE_HUILE',
    'ROUE_DEJANTEE',
    'SUSPENSION_AMORTISSEUR',
  ],
  'SCOOTER_THERM': [
    'CREVAISON_PNEU',
    'DEMARRAGE_BATTERIE',
    'COURROIE_CASSEE',
    'TRANSMISSION_CABLE',
    'SURCHAUFFE_CALAGE',
    'CARBURANT_EPUISE',
    'FREIN_MOTO',
    'ECLAIRAGE_CLAXON',
    'FUITE_HUILE',
    'ROUE_DEJANTEE',
    'SUSPENSION_AMORTISSEUR',
  ],
  'CLOBOTO_PAX': [
    'CREVAISON_PNEU',
    'DEMARRAGE_BATTERIE',
    'CHAINE_CASSEE',
    'TRANSMISSION_CABLE',
    'SURCHAUFFE_CALAGE',
    'CARBURANT_EPUISE',
    'FREIN_MOTO',
    'ECLAIRAGE_CLAXON',
    'FUITE_HUILE',
    'ROUE_DEJANTEE',
    'SUSPENSION_AMORTISSEUR',
  ],
  'KLOBOTO_FRET': [
    'CREVAISON_PNEU',
    'DEMARRAGE_BATTERIE',
    'CHAINE_CASSEE',
    'TRANSMISSION_CABLE',
    'SURCHAUFFE_CALAGE',
    'CARBURANT_EPUISE',
    'FREIN_MOTO',
    'ECLAIRAGE_CLAXON',
    'FUITE_HUILE',
    'ROUE_DEJANTEE',
    'SUSPENSION_AMORTISSEUR',
  ],
  // Moto / Scooter / Voiture Électrique
  'E_MOTO': [
    'BATTERIE_VIDE',
    'BMS_CONTROLEUR',
    'CREVAISON_ROUE_BLOQUEE',
    'REMORQUAGE_PLATEAU',
    'FREIN_MOTO',
    'ECLAIRAGE_CLAXON',
  ],
  'E_SCOOTER': [
    'BATTERIE_VIDE',
    'BMS_CONTROLEUR',
    'CREVAISON_ROUE_BLOQUEE',
    'REMORQUAGE_PLATEAU',
    'FREIN_MOTO',
    'ECLAIRAGE_CLAXON',
  ],
  'E_CAR': [
    'BATTERIE_VIDE',
    'BMS_CONTROLEUR',
    'CREVAISON_ROUE_BLOQUEE',
    'REMORQUAGE_PLATEAU',
  ],
  // Voiture / Utilitaire / Minibus / Bus
  'CAR_THERM': [
    'BATTERIE_ALTERNATEUR',
    'CREVAISON_VL',
    'SURCHAUFFE_FUITE',
    'FREIN_EMBRAYAGE_COURROIE',
    'REMORQUAGE_VL',
    'CARBURANT_EPUISE',
    'ECLAIRAGE_CLAXON',
    'FUITE_HUILE',
    'SUSPENSION_AMORTISSEUR',
  ],
  'UTILITAIRE_VAN': [
    'BATTERIE_ALTERNATEUR',
    'CREVAISON_VL',
    'SURCHAUFFE_FUITE',
    'FREIN_EMBRAYAGE_COURROIE',
    'REMORQUAGE_VL',
    'CARBURANT_EPUISE',
    'ECLAIRAGE_CLAXON',
    'FUITE_HUILE',
    'SUSPENSION_AMORTISSEUR',
  ],
  'MINIBUS': [
    'BATTERIE_ALTERNATEUR',
    'CREVAISON_VL',
    'SURCHAUFFE_FUITE',
    'FREIN_EMBRAYAGE_COURROIE',
    'REMORQUAGE_VL',
    'CARBURANT_EPUISE',
    'ECLAIRAGE_CLAXON',
    'FUITE_HUILE',
    'SUSPENSION_AMORTISSEUR',
  ],
  'BUS_TRANSPORT': [
    'BATTERIE_ALTERNATEUR',
    'CREVAISON_VL',
    'SURCHAUFFE_FUITE',
    'FREIN_EMBRAYAGE_COURROIE',
    'REMORQUAGE_VL',
    'CARBURANT_EPUISE',
    'ECLAIRAGE_CLAXON',
    'FUITE_HUILE',
    'SUSPENSION_AMORTISSEUR',
  ],
  // Poids Lourds & Camions
  'CAMION_6_ROUES': [
    'PNEU_PL',
    'FREIN_AIR_PL',
    'ENERGIE_24V',
    'MECA_LOURDE_PL',
    'REMORQUAGE_PL',
    'CARBURANT_EPUISE',
  ],
  'CAMION_10_ROUES': [
    'PNEU_PL',
    'FREIN_AIR_PL',
    'ENERGIE_24V',
    'MECA_LOURDE_PL',
    'REMORQUAGE_PL',
    'CARBURANT_EPUISE',
  ],
  'SEMI_REMORQUE': [
    'PNEU_PL',
    'FREIN_AIR_PL',
    'ENERGIE_24V',
    'MECA_LOURDE_PL',
    'REMORQUAGE_PL',
    'CARBURANT_EPUISE',
  ],
};

List<String> sosPanneCodesPour(String codeVehicule) =>
    kSosPannesParVehicule[codeVehicule.trim().toUpperCase()] ?? const [];

bool sosPanneCompatible({required String vehicule, required String panne}) =>
    sosPanneCodesPour(vehicule).contains(panne.trim().toUpperCase());

/// Diagnostic professionnel par type de panne : quel métier intervient,
/// quel service express est mobilisé et le conseil immédiat donné au
/// client. Les codes sont ceux de sos_pannes (migration sos/03).
const Map<String, ({String metier, String service, String conseil})>
kDiagnosticParPanne = {
  'CREVAISON_PNEU': (
    metier: 'Vulcanisateur pneu',
    service: 'Vulcanisateur express mobile',
    conseil:
        'Roulez doux jusqu\'au bord de la route ; le vulcanisateur '
        'vient avec rustines et compresseur.',
  ),
  'DEMARRAGE_BATTERIE': (
    metier: 'Électricien auto & moto',
    service: 'Atelier mobile léger',
    conseil:
        'Ne relancez pas le démarreur en continu ; l\'électricien '
        'arrive avec batterie de démarrage.',
  ),
  'TRANSMISSION_CABLE': (
    metier: 'Mécanicien moto',
    service: 'Atelier mobile léger',
    conseil:
        'Ne forcez pas la transmission ; un câble ou une chaîne '
        'cassée se remplace sur place.',
  ),
  'COURROIE_CASSEE': (
    metier: 'Mécanicien moto',
    service: 'Atelier mobile léger',
    conseil:
        'Scooter à courroie : ne forcez plus les accélérations ; '
        'le mécanicien arrive avec la courroie de rechange.',
  ),
  'CHAINE_CASSEE': (
    metier: 'Mécanicien moto',
    service: 'Atelier mobile léger',
    conseil:
        'Moto à vitesses, chaîne cassée : poussez le véhicule hors '
        'de la chaussée ; kit chaîne remplacé sur place.',
  ),
  'CARBURANT_EPUISE': (
    metier: 'Vendeur de carburant / dépanneur',
    service: 'Atelier mobile léger',
    conseil:
        "Panne sèche : n'insistez pas sur le démarreur ; le dépanneur "
        "arrive avec un bidon d'essence homologué.",
  ),
  'FREIN_MOTO': (
    metier: 'Mécanicien moto',
    service: 'Atelier mobile léger',
    conseil:
        'Freins douteux : ne roulez plus ; garnitures et câbles '
        'remplacés sur place.',
  ),
  'ECLAIRAGE_CLAXON': (
    metier: 'Électricien auto & moto',
    service: 'Atelier mobile léger',
    conseil:
        'La nuit, gilet + triangle ; ampoules, fusibles et klaxon '
        'remis en service sur place.',
  ),
  'FUITE_HUILE': (
    metier: 'Mécanicien moto & véhicule léger',
    service: 'Atelier mobile léger',
    conseil:
        "Moteur coupé, ne roulez pas : recherche de fuite et joints "
        'sur place.',
  ),
  'ROUE_DEJANTEE': (
    metier: 'Vulcanisateur pneu',
    service: 'Vulcanisateur express mobile',
    conseil:
        'Roue déjantée : déjantage et redressage sur place par le '
        'vulcanisateur.',
  ),
  'SUSPENSION_AMORTISSEUR': (
    metier: 'Mécanicien moto & véhicule léger',
    service: 'Atelier mobile léger',
    conseil:
        'Amortisseur cassé : roulez très lentement jusqu\'au bord ; '
        'remplacement sur place ou remorquage.',
  ),
  'SURCHAUFFE_CALAGE': (
    metier: 'Mécanicien moto',
    service: 'Atelier mobile léger',
    conseil:
        'Moteur coupé, laissez refroidir ; contrôle du carburant '
        'et du refroidissement sur place.',
  ),
  'BATTERIE_VIDE': (
    metier: 'Technicien véhicule électrique',
    service: 'Prestataire certifié électrique / swap',
    conseil:
        'Batterie à plat : échange (swap) ou recharge '
        'd\'urgence sur place.',
  ),
  'BMS_CONTROLEUR': (
    metier: 'Technicien véhicule électrique',
    service: 'Prestataire certifié électrique / swap',
    conseil:
        'Panne électronique : diagnostic BMS/contrôleur, '
        'immobilisez le véhicule.',
  ),
  'CREVAISON_ROUE_BLOQUEE': (
    metier: 'Technicien véhicule électrique',
    service: 'Prestataire certifié électrique / swap',
    conseil:
        'Roue bloquée : n\'insistez pas, intervention spéciale '
        'moteur électrique.',
  ),
  'REMORQUAGE_PLATEAU': (
    metier: 'Dépanneuse / Remorquage',
    service: 'Dépanneuse plateau',
    conseil:
        'Véhicule immobilisé : remorquage jusqu\'au garage ou '
        'au domicile (400 FCFA/km).',
  ),
  'BATTERIE_ALTERNATEUR': (
    metier: 'Électricien auto & moto',
    service: 'Atelier mobile léger',
    conseil:
        'Test batterie + alternateur sur place, démarrage '
        'assuré si la batterie est simplement déchargée.',
  ),
  'CREVAISON_VL': (
    metier: 'Vulcanisateur pneu',
    service: 'Vulcanisateur express mobile',
    conseil:
        'Cric et roue de secours : le vulcanisateur VL répare '
        'ou remplace sur place.',
  ),
  'SURCHAUFFE_FUITE': (
    metier: 'Mécanicien véhicule léger',
    service: 'Garage / mécanique générale',
    conseil:
        'Moteur coupé immédiatement ; recherche de fuite et '
        'liquide de refroidissement sur place.',
  ),
  'FREIN_EMBRAYAGE_COURROIE': (
    metier: 'Mécanicien véhicule léger',
    service: 'Garage / mécanique générale',
    conseil:
        'Frein ou embrayage douteux : ne roulez plus, '
        'réparation sur place ou remorquage.',
  ),
  'REMORQUAGE_VL': (
    metier: 'Dépanneuse / Remorquage',
    service: 'Dépanneuse Véhicule Léger',
    conseil:
        'Remorquage voiture/utilitaire jusqu\'au garage '
        '(400 FCFA/km).',
  ),
  'PNEU_PL': (
    metier: 'Vulcanisateur Poids Lourd',
    service: 'Vulcanisateur mobile Poids Lourd',
    conseil:
        'Pneu PL : équipement lourd requis, tenez-vous '
        'à distance de la roue.',
  ),
  'FREIN_AIR_PL': (
    metier: 'Spécialiste freinage pneumatique PL',
    service: 'Mécanicien PL / camion-atelier',
    conseil:
        'Circuit d\'air : gardez le véhicule immobilisé, '
        'cales posées.',
  ),
  'ENERGIE_24V': (
    metier: 'Électricien Poids Lourd',
    service: 'Mécanicien PL / camion-atelier',
    conseil:
        'Démarrage 24V : batteries en parallèle, '
        'ne court-circuitez rien.',
  ),
  'MECA_LOURDE_PL': (
    metier: 'Mécanicien Poids Lourd',
    service: 'Mécanicien PL / camion-atelier',
    conseil:
        'Panne mécanique lourde : camion-atelier sur site, '
        'pièces lourdes à commander si besoin.',
  ),
  'REMORQUAGE_PL': (
    metier: 'Dépanneuse / Remorquage',
    service: 'Dépanneuse Poids Lourd',
    conseil:
        'Remorquage lourd tonnage : balisage renforcé, '
        'éloignez-vous de la voie.',
  ),
};

/// Diagnostic pro pour un code de panne (null si code inconnu).
({String metier, String service, String conseil})? diagnosticPourPanne(
  String? code,
) {
  if (code == null) return null;
  return kDiagnosticParPanne[code.trim().toUpperCase()];
}

/// Libellés affichés des compétences (codes = sos_competences en base).
const Map<String, String> kSosCompetences = {
  'PNEU_MOTO': 'Vulcanisateur moto / deux-trois roues',
  'PNEU_VL': 'Vulcanisateur véhicules légers',
  'PNEU_PL': 'Vulcanisateur Poids Lourd (équipement lourd tonnage)',
  'ELEC_AUTO': 'Électricien auto & moto (12V)',
  'ELEC_VEHICULE_HAB': 'Technicien véhicules électriques (BMS / contrôleur)',
  'MECANIQUE_MOTO': 'Mécanicien moto / deux-trois roues',
  'MECANIQUE_VL': 'Mécanicien véhicules légers',
  'MECA_LOURDE_PL': 'Mécanicien Poids Lourd (camion-atelier)',
  'FREIN_AIR_PL': "Circuit d'air & freinage pneumatique PL",
  'DIAG_24V_PL': 'Diagnostic & démarrage 24V Poids Lourd',
  'REMORQUAGE_VL': 'Remorquage / dépanneuse VL',
  'REMORQUAGE_PL': 'Remorquage Poids Lourd (dépanneuse lourd tonnage)',
  'SWAP_BATTERIE': 'Échange / swap de batterie électrique',
  'LIVRAISON_CARBURANT': 'Livraison de carburant express (panne sèche)',
};

/// Services de prestation express et habilitations requises par code.
const Map<String, List<String>> kSosServicesHabilitations = {
  'VULCANISATEUR_EXPRESS': [],
  'ATELIER_MOBILE_LEGER': [],
  'TECH_ELECTRIQUE': ['HAB_ELECTRIQUE'],
  'GARAGE_MECANIQUE': [],
  'DEPANNEUSE_VL': ['HAB_DEPANNEUSE_VL'],
  'VULCANISATEUR_PL': [],
  'CAMION_ATELIER_PL': [],
  'DEPANNEUSE_PL': ['HAB_DEPANNEUSE_PL'],
};

const Map<String, String> kSosServicesLibelles = {
  'VULCANISATEUR_EXPRESS': 'Vulcanisateur express mobile',
  'ATELIER_MOBILE_LEGER': 'Atelier mobile léger / technicien',
  'TECH_ELECTRIQUE': 'Prestataire certifié électrique / swap',
  'GARAGE_MECANIQUE': 'Garage / mécanique générale',
  'DEPANNEUSE_VL': 'Dépanneuse Véhicule Léger (remorquage)',
  'VULCANISATEUR_PL': 'Vulcanisateur mobile Poids Lourd',
  'CAMION_ATELIER_PL': 'Mécanicien PL mobile / camion-atelier sur site',
  'DEPANNEUSE_PL': 'Dépanneuse Poids Lourd (remorquage lourd tonnage)',
};

const Map<String, String> kSosHabilitationsLibelles = {
  'HAB_ELECTRIQUE': 'Habilitation Électrique',
  'HAB_DEPANNEUSE_VL': 'Dépanneuse Véhicule Léger',
  'HAB_DEPANNEUSE_PL': 'Dépanneuse Poids Lourd',
};

String sosServiceLibelle(String code) => kSosServicesLibelles[code] ?? code;

String sosHabilitationLibelle(String code) =>
    kSosHabilitationsLibelles[code] ?? code;

String sosCompetenceLibelle(String code) => kSosCompetences[code] ?? code;
