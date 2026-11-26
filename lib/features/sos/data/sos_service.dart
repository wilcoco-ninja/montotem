import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/features/sos/domain/sos_constants.dart';

/// Exception métier du module SOS. [code] reprend les codes renvoyés par
/// la base (PANNE_INCOMPATIBLE, NON_CONNECTE, PRESTATAIRE_INCOMPATIBLE...).
class SosException implements Exception {
  const SosException(this.message, {this.code});
  final String message;
  final String? code;

  @override
  String toString() => message;
}

@immutable
class SosDevis {
  const SosDevis({
    required this.mainOeuvreFcfa,
    required this.pieceCode,
    required this.pieceLibelle,
    required this.piecePrixFcfa,
    required this.pieceStock,
    required this.deplacementFcfa,
    required this.totalFcfa,
    required this.tarifKmGaranti,
  });

  final int mainOeuvreFcfa;
  final String? pieceCode;
  final String? pieceLibelle;
  final int piecePrixFcfa;
  final int pieceStock;
  final int deplacementFcfa;
  final int totalFcfa;

  /// Tarif au km garanti du prestataire (FCFA/km).
  final int tarifKmGaranti;

  factory SosDevis.fromJson(Map<String, dynamic> j) => SosDevis(
    mainOeuvreFcfa: (j['main_oeuvre_fcfa'] as num?)?.toInt() ?? 0,
    pieceCode: j['piece_code'] as String?,
    pieceLibelle: j['piece_libelle'] as String?,
    piecePrixFcfa: (j['piece_prix_fcfa'] as num?)?.toInt() ?? 0,
    pieceStock: (j['piece_stock'] as num?)?.toInt() ?? 0,
    deplacementFcfa: (j['deplacement_fcfa'] as num?)?.toInt() ?? 0,
    totalFcfa: (j['total_fcfa'] as num?)?.toInt() ?? 0,
    tarifKmGaranti: (j['tarif_km_garanti'] as num?)?.toInt() ?? 0,
  );
}

@immutable
class SosPrestataire {
  const SosPrestataire({
    required this.id,
    required this.nom,
    required this.metier,
    required this.distanceKm,
    required this.devis,
    required this.services,
    required this.competences,
    required this.habilitations,
    this.businessName,
    this.telephone,
    this.noteMoyenne = 0,
    this.rayonMaxKm = 15,
  });

  final String id;
  final String nom;
  final String? businessName;
  final String metier;
  final String? telephone;
  final double noteMoyenne;
  final double distanceKm;
  final int rayonMaxKm;
  final SosDevis devis;
  final List<String> services;
  final List<String> competences;
  final List<String> habilitations;

  String get nomAffiche =>
      (businessName != null && businessName!.trim().isNotEmpty)
      ? businessName!
      : nom;
}

SosException _exception(Exception e) {
  if (e is PostgrestException) {
    final m = e.message;
    if (m.contains('PANNE_INCOMPATIBLE')) {
      return const SosException(
        'Cette panne n\'est pas compatible avec ce type de véhicule.',
        code: 'PANNE_INCOMPATIBLE',
      );
    }
    if (m.contains('PRESTATAIRE_INCOMPATIBLE')) {
      return const SosException(
        'Ce dépanneur ne couvre pas votre panne. Rouvrez la recherche.',
        code: 'PRESTATAIRE_INCOMPATIBLE',
      );
    }
    if (m.contains('NON_CONNECTE')) {
      return const SosException(
        'Session expirée. Reconnectez-vous.',
        code: 'NON_CONNECTE',
      );
    }
    if (m.contains('INTROUVABLE')) {
      return const SosException('Demande introuvable.', code: 'INTROUVABLE');
    }
    return SosException('Opération impossible. Réessayez.', code: e.code);
  }
  if (e is SosException) {
    return e;
  }
  return const SosException(
    'Connexion impossible. Vérifiez votre réseau et réessayez.',
    code: 'RESEAU',
  );
}

/// Service du module « SOS Je Suis En Panne ».
///
/// Toute la logique métier (compatibilité panne ↔ véhicule, habilitations,
/// stock des pièces, devis) est validée côté PostgreSQL :
///   - `sos_pannes_pour_vehicule(vehicule)` : pannes autorisées ;
///   - `sos_match_providers(vehicule, panne, lat, lng, ...)` : prestataires
///     + devis pré-calculé côté serveur ;
///   - `sos_demander_intervention(...)` : commande, devis figé.
class SosService {
  SupabaseClient get _sb => Supabase.instance.client;

  SosService._();

  static final SosService instance = SosService._();

  /// Pannes autorisées pour un véhicule. Source locale (constantes) avec
  /// synchronisation depuis la base pour rester aligné si la matrice évolue.
  Future<List<SosPanne>> pannesPour(SosVehicule vehicule) async {
    final codesLocaux = sosPanneCodesPour(vehicule.code);
    final locales = const ParCode().pannes
        .where((p) => codesLocaux.contains(p.code))
        .toList();
    try {
      final data = await _sb.rpc(
        'sos_pannes_pour_vehicule',
        params: {'p_vehicule': vehicule.code},
      );
      if (data is List) {
        final serveur = data
            .whereType<Map>()
            .map((e) => SosPanne.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        if (serveur.isNotEmpty) return serveur;
      }
    } catch (_) {
      // le filtre local reste valide si la base est injoignable.
    }
    return locales;
  }

  /// Prestataires compatibles autour de la position, avec devis pré-calculé
  /// et garanti par le serveur.
  Future<List<SosPrestataire>> rechercherPrestataires({
    required SosVehicule vehicule,
    required SosPanne panne,
    required double latitude,
    required double longitude,
    double rayonKm = 15,
    int limite = 8,
  }) async {
    try {
      final data = await _sb.rpc(
        'sos_match_providers',
        params: {
          'p_vehicule': vehicule.code,
          'p_panne': panne.code,
          'p_lat': latitude,
          'p_lng': longitude,
          'p_rayon_km': rayonKm,
          'p_limit': limite,
        },
      );
      if (data is! List) {
        return const [];
      }
      final prestataires = data.whereType<Map>().map((e) {
        final j = Map<String, dynamic>.from(e);
        final devis = SosDevis.fromJson(
          Map<String, dynamic>.from(j['devis'] as Map? ?? const {}),
        );
        return SosPrestataire(
          id: '${j['id'] ?? ''}',
          nom: '${j['nom'] ?? 'Prestataire'}',
          businessName: j['business_name'] as String?,
          metier: '${j['metier'] ?? ''}',
          telephone: j['telephone'] as String?,
          noteMoyenne: (j['note_moyenne'] as num?)?.toDouble() ?? 0,
          distanceKm: (j['distance_km'] as num?)?.toDouble() ?? 0,
          rayonMaxKm: (j['rayon_max_km'] as num?)?.toInt() ?? 15,
          devis: devis,
          services:
              (j['sos_services'] as List?)?.map((s) => '$s').toList() ??
              const [],
          competences:
              (j['competences'] as List?)?.map((s) => '$s').toList() ??
              const [],
          habilitations:
              (j['habilitations'] as List?)?.map((s) => '$s').toList() ??
              const [],
        );
      }).toList();
      // garde-fou : jamais de ligne avec un id vide.
      prestataires.removeWhere((p) => p.id.isEmpty);
      return prestataires;
    } on Exception catch (e) {
      throw _exception(e);
    }
  }

  /// Commande l'intervention : le serveur revérifie tout et fige le devis.
  Future<String> demanderIntervention({
    required SosVehicule vehicule,
    required SosPanne panne,
    required double latitude,
    required double longitude,
    required String prestataireId,
    SosNiveauSecurite? niveau,
    String? repereLocal,
    String? description,
  }) async {
    try {
      final id = await _sb.rpc(
        'sos_demander_intervention',
        params: {
          'p_vehicule': vehicule.code,
          'p_panne': panne.code,
          'p_lat': latitude,
          'p_lng': longitude,
          'p_prestataire': prestataireId,
          'p_niveau_securite': niveau?.code,
          'p_repere_local': repereLocal,
          'p_description': (description ?? '').trim().isEmpty
              ? null
              : (description ?? '').trim(),
        },
      );
      return '$id';
    } catch (e) {
      if (e is Exception) {
        throw _exception(e);
      }
      rethrow;
    }
  }

  /// Journalise chaque panne décrite par un usager (toutes les pannes
  /// rencontrées sur les routes sont enregistrées pour affiner le
  /// diagnostic rapide et les pièces à emporter). Ne lève jamais : la
  /// journalisation ne doit jamais bloquer le dépannage.
  Future<void> journaliserPanne({
    required SosVehicule vehicule,
    required SosPanne panne,
    String? description,
    double? latitude,
    double? longitude,
  }) async {
    try {
      await _sb.rpc(
        'sos_journaliser_panne',
        params: {
          'p_vehicule': vehicule.code,
          'p_panne': panne.code,
          'p_description': (description ?? '').trim().isEmpty
              ? null
              : (description ?? '').trim(),
          'p_lat': latitude,
          'p_lng': longitude,
        },
      );
    } catch (_) {
      // Silencieux : la statistique est utile, pas bloquante.
    }
  }
}

/// Référentiel local des pannes (miroir des constantes) pour filtrer sans
/// réseau au premier rendu de l'étape 3.
class ParCode {
  const ParCode();

  List<SosPanne> get pannes => const [
    SosPanne(
      code: 'CREVAISON_PNEU',
      libelle: 'Crevaison / Pneu / Chambre à air',
      description: 'Tubeless ou chambre à air d\'origine.',
      mainOeuvreFcfa: 2000,
      pieceObligatoire: true,
      pieceCode: 'CHAMBRE_AIR_MOTO',
      pieceLibelle: 'Chambre à air / pneu moto',
      icone: Icons.tire_repair_rounded,
    ),
    SosPanne(
      code: 'DEMARRAGE_BATTERIE',
      libelle: 'Panne de démarrage / Batterie / Bougie / Allumage',
      description: 'Diagnostic allumage et charge.',
      mainOeuvreFcfa: 3000,
      pieceObligatoire: false,
      pieceCode: 'BOUGIE_MOTO',
      pieceLibelle: 'Bougie / batterie 12V moto',
      icone: Icons.battery_alert_rounded,
    ),
    SosPanne(
      code: 'TRANSMISSION_CABLE',
      libelle: 'Câble d\'embrayage, frein, chaîne ou courroie cassée',
      description: 'Remplacement à l\'arrêt.',
      mainOeuvreFcfa: 3000,
      pieceObligatoire: false,
      pieceCode: 'CABLE_FREIN_MOTO',
      pieceLibelle: 'Câble / chaîne / courroie',
      icone: Icons.link_off_rounded,
    ),
    SosPanne(
      code: 'SURCHAUFFE_CALAGE',
      libelle: 'Surchauffe ou calage moteur',
      description: 'Diagnostic thermique et redémarrage.',
      mainOeuvreFcfa: 3000,
      pieceObligatoire: false,
      icone: Icons.thermostat_rounded,
    ),
    SosPanne(
      code: 'COURROIE_CASSEE',
      libelle: "Courroie de scooter cassée (scooter : juste accélérer)",
      description: "Transmission variateur-courroie : remplacement sur place.",
      mainOeuvreFcfa: 3500,
      pieceObligatoire: true,
      pieceCode: 'COURROIE_SCOOTER',
      pieceLibelle: 'Courroie de transmission scooter',
      icone: Icons.settings_rounded,
    ),
    SosPanne(
      code: 'CHAINE_CASSEE',
      libelle: "Chaîne cassée (moto à vitesses)",
      description: 'Kit chaîne : dérivation ou remplacement sur place.',
      mainOeuvreFcfa: 4000,
      pieceObligatoire: true,
      pieceCode: 'KIT_CHAINE_MOTO',
      pieceLibelle: 'Kit chaîne moto (chaîne + pignons)',
      icone: Icons.link_off_rounded,
    ),
    SosPanne(
      code: 'CARBURANT_EPUISE',
      libelle: "Panne sèche : plus d'essence / carburant épuisé",
      description: "Le dépanneur arrive avec un bidon d'essence homologué.",
      mainOeuvreFcfa: 2000,
      pieceObligatoire: false,
      icone: Icons.local_gas_station_rounded,
    ),
    SosPanne(
      code: 'FREIN_MOTO',
      libelle: 'Freins défaillants (moto, scooter, tricycle)',
      description: 'Garnitures, câble ou circuit de frein.',
      mainOeuvreFcfa: 3500,
      pieceObligatoire: false,
      pieceCode: 'GARNITURE_FREIN_MOTO',
      pieceLibelle: 'Garnitures / plaquettes de frein',
      icone: Icons.stop_circle_rounded,
    ),
    SosPanne(
      code: 'ECLAIRAGE_CLAXON',
      libelle: 'Éclairage, klaxon ou clignotants en panne',
      description: 'Ampoules, fusibles, faisceau, klaxon.',
      mainOeuvreFcfa: 2500,
      pieceObligatoire: false,
      pieceCode: 'AMPOULE_FUSIBLE',
      pieceLibelle: 'Ampoule / fusible / faisceau',
      icone: Icons.highlight_rounded,
    ),
    SosPanne(
      code: 'FUITE_HUILE',
      libelle: "Fuite d'huile ou de carburant",
      description: 'Recherche de fuite, joints et resserrage.',
      mainOeuvreFcfa: 4000,
      pieceObligatoire: false,
      pieceCode: 'JOINT_MOTO',
      pieceLibelle: 'Joints / visserie moteur',
      icone: Icons.opacity_rounded,
    ),
    SosPanne(
      code: 'ROUE_DEJANTEE',
      libelle: 'Roue déjantée / jante voilée',
      description: 'Déjantage, redressage ou remplacement de jante.',
      mainOeuvreFcfa: 3000,
      pieceObligatoire: false,
      icone: Icons.album_rounded,
    ),
    SosPanne(
      code: 'SUSPENSION_AMORTISSEUR',
      libelle: 'Suspension / amortisseur cassé',
      description: 'Amortisseur, silentbloc ou fourche.',
      mainOeuvreFcfa: 5000,
      pieceObligatoire: false,
      pieceCode: 'AMORTISSEUR_PIECE',
      pieceLibelle: 'Amortisseur / silentbloc',
      icone: Icons.compress_rounded,
    ),
    SosPanne(
      code: 'BATTERIE_VIDE',
      libelle: 'Batterie déchargée / Perte d\'autonomie sur la route',
      description: 'Swap ou recharge d\'appoint.',
      mainOeuvreFcfa: 2500,
      pieceObligatoire: false,
      pieceCode: 'BATTERIE_ELEC',
      pieceLibelle: 'Batterie / faisceau swap',
      icone: Icons.battery_alert_rounded,
    ),
    SosPanne(
      code: 'BMS_CONTROLEUR',
      libelle: 'Alerte BMS / Contrôleur / Coupure de puissance',
      description: 'Diagnostic électronique habilité.',
      mainOeuvreFcfa: 4000,
      pieceObligatoire: false,
      icone: Icons.developer_board_rounded,
    ),
    SosPanne(
      code: 'CREVAISON_ROUE_BLOQUEE',
      libelle: 'Crevaison / Roue bloquée',
      description: 'Pneu tubeless ou roue greffée.',
      mainOeuvreFcfa: 3000,
      pieceObligatoire: true,
      pieceCode: 'CHAMBRE_AIR_MOTO',
      pieceLibelle: 'Chambre à air / pneu',
      icone: Icons.tire_repair_rounded,
    ),
    SosPanne(
      code: 'REMORQUAGE_PLATEAU',
      libelle: 'Remorquage plateau (immobilisation complète)',
      description: 'Plateau VL vers l\'atelier le plus proche.',
      mainOeuvreFcfa: 5000,
      pieceObligatoire: false,
      icone: Icons.local_shipping_rounded,
    ),
    SosPanne(
      code: 'BATTERIE_ALTERNATEUR',
      libelle: 'Batterie à plat / Alternateur / Démarreur',
      description: 'Boost ou remplacement.',
      mainOeuvreFcfa: 4000,
      pieceObligatoire: false,
      pieceCode: 'BATTERIE_VL',
      pieceLibelle: 'Batterie 12V véhicule léger',
      icone: Icons.battery_alert_rounded,
    ),
    SosPanne(
      code: 'CREVAISON_VL',
      libelle: 'Crevaison / Éclatement de pneu / Roue de secours absente',
      description: 'Roue de secours ou réparation tubeless.',
      mainOeuvreFcfa: 3000,
      pieceObligatoire: false,
      pieceCode: 'PNEU_VL',
      pieceLibelle: 'Pneu véhicule léger',
      icone: Icons.tire_repair_rounded,
    ),
    SosPanne(
      code: 'SURCHAUFFE_FUITE',
      libelle: 'Surchauffe moteur / Fuite liquide de refroidissement ou huile',
      description: 'Diagnostic et colmatage / durite.',
      mainOeuvreFcfa: 4500,
      pieceObligatoire: false,
      icone: Icons.water_drop_rounded,
    ),
    SosPanne(
      code: 'FREIN_EMBRAYAGE_COURROIE',
      libelle: 'Problème freinage, embrayage ou courroie',
      description: 'Remplacement/pièce selon usure.',
      mainOeuvreFcfa: 4500,
      pieceObligatoire: false,
      pieceCode: 'COURROIE_VL',
      pieceLibelle: 'Courroie / plaquettes',
      icone: Icons.disc_full_rounded,
    ),
    SosPanne(
      code: 'REMORQUAGE_VL',
      libelle: 'Véhicule immobilisé → Dépanneuse / Remorquage',
      description: 'Dépanneuse VL, tarif au km garanti.',
      mainOeuvreFcfa: 5000,
      pieceObligatoire: false,
      icone: Icons.local_shipping_rounded,
    ),
    SosPanne(
      code: 'PNEU_PL',
      libelle: 'Pneumatique Poids Lourd : Crevaison / Éclatement pneu jumelé ou essieu',
      description: 'Nécessite cric hydraulique lourd / clé à chocs PL.',
      mainOeuvreFcfa: 12000,
      pieceObligatoire: false,
      pieceCode: 'VALVE_PL',
      pieceLibelle: 'Valve / chambre à air / pneu PL',
      icone: Icons.tire_repair_rounded,
    ),
    SosPanne(
      code: 'FREIN_AIR_PL',
      libelle: 'Circuit d\'air & Freinage pneumatique : Chute de pression d\'air, fuite flexible, frein de parc bloqué',
      description: 'Intervention sur circuit d\'air.',
      mainOeuvreFcfa: 15000,
      pieceObligatoire: false,
      pieceCode: 'FLEXIBLE_AIR_PL',
      pieceLibelle: 'Flexible / valve circuit d\'air PL',
      icone: Icons.air_rounded,
    ),
    SosPanne(
      code: 'ENERGIE_24V',
      libelle: 'Énergie & Démarrage 24V : Batteries 24V à plat (couplage double batterie), alternateur ou démarreur lourd',
      description: 'Couplage double batterie / alternateur.',
      mainOeuvreFcfa: 12000,
      pieceObligatoire: false,
      pieceCode: 'BATTERIE_24V',
      pieceLibelle: 'Batterie 24V PL',
      icone: Icons.battery_charging_full_rounded,
    ),
    SosPanne(
      code: 'MECA_LOURDE_PL',
      libelle: 'Mécanique lourde & Transmission : Surchauffe moteur / durite éclatée, casse arbre de transmission, embrayage ou boîte de vitesses',
      description: 'Diagnostic PL + intervention.',
      mainOeuvreFcfa: 20000,
      pieceObligatoire: false,
      icone: Icons.precision_manufacturing_rounded,
    ),
    SosPanne(
      code: 'REMORQUAGE_PL',
      libelle: 'Immobilisation totale : Remorquage Poids Lourd (dépanneuse lourd tonnage / bras de levage)',
      description: 'Prise en charge lourd tonnage, tarif au km garanti.',
      mainOeuvreFcfa: 25000,
      pieceObligatoire: false,
      icone: Icons.local_shipping_rounded,
    ),
    SosPanne(
      code: 'EMBRAYAGE_PATINE',
      libelle: 'Embrayage qui patine (tricycle surchargé)',
      description:
          'Le moteur monte dans les tours mais le tricycle n\'avance plus.',
      mainOeuvreFcfa: 4000,
      pieceObligatoire: false,
      pieceCode: 'DISQUE_EMBRAYAGE',
      pieceLibelle: 'Disque d\'embrayage / garnitures',
      icone: Icons.sync_problem_rounded,
    ),
    SosPanne(
      code: 'PONT_DIFFERENTIEL',
      libelle: 'Pont / différentiel arrière bruyant ou bloqué (tricycle)',
      description: 'Claquements à l\'accélération, roue arrière qui se bloque.',
      mainOeuvreFcfa: 5000,
      pieceObligatoire: false,
      pieceCode: 'HUILE_PONT',
      pieceLibelle: 'Huile de pont / joint spi',
      icone: Icons.settings_suggest_rounded,
    ),
    SosPanne(
      code: 'CARBURATEUR_BOUGIE',
      libelle: 'Carburateur encrassé / bougie noyée / filtre à air bouché',
      description: 'Démarrages difficiles, moteur qui cale, ralenti instable.',
      mainOeuvreFcfa: 3000,
      pieceObligatoire: false,
      pieceCode: 'KIT_CARBURATION',
      pieceLibelle: 'Kit carburation (bougie, filtre, joints)',
      icone: Icons.blur_circular_rounded,
    ),
    SosPanne(
      code: 'REGULATEUR_CHARGE',
      libelle: 'Batterie qui ne charge plus / régulateur grillé',
      description: 'Phares faibles, batterie morte en répétition malgré un remplacement.',
      mainOeuvreFcfa: 3500,
      pieceObligatoire: false,
      pieceCode: 'REGULATEUR_TENSION',
      pieceLibelle: 'Régulateur de tension / redresseur',
      icone: Icons.bolt_rounded,
    ),
    SosPanne(
      code: 'SERRAGE_MOTEUR',
      libelle: 'Serrage moteur / fumée bleue ou blanche (haut moteur)',
      description:
          'Manque d\'huile ou surchauffe : segments usés, perte de puissance.',
      mainOeuvreFcfa: 10000,
      pieceObligatoire: false,
      pieceCode: 'REVISION_HAUT_MOTEUR',
      pieceLibelle: 'Segments, joints, huile moteur',
      icone: Icons.report_rounded,
    ),
    SosPanne(
      code: 'VOYANT_MOTEUR_CAPTEUR',
      libelle:
          'Voyant moteur allumé / capteur défaillant (diagnostic électronique)',
      description:
          'Diagnostic valise OBD2 : capteurs PMH, débitmètre, sonde lambda.',
      mainOeuvreFcfa: 3500,
      pieceObligatoire: false,
      icone: Icons.memory_rounded,
    ),
    SosPanne(
      code: 'INJECTION_DIESEL',
      libelle: 'Pompe ou injecteurs diesel grippés (Common Rail)',
      description:
          'Pertes de puissance, fumée noire, démarrage diesel difficile.',
      mainOeuvreFcfa: 7000,
      pieceObligatoire: false,
      pieceCode: 'FILTRE_GASOIL',
      pieceLibelle: 'Filtre à gasoil / injecteur',
      icone: Icons.oil_barrel_outlined,
    ),
    SosPanne(
      code: 'TRAIN_ROULANT_VL',
      libelle: 'Rotules, silentblocs, cardans ou roulements (claquements)',
      description: 'Jeux dans la direction, claquements sur routes dégradées.',
      mainOeuvreFcfa: 6000,
      pieceObligatoire: false,
      pieceCode: 'ROTULE_SILENTBLOC',
      pieceLibelle: 'Rotule / silentbloc / roulement',
      icone: Icons.shuffle_rounded,
    ),
    SosPanne(
      code: 'SUSPENSION_PL',
      libelle: 'Lames de ressort, coussins d\'air, balanciers (Poids Lourd)',
      description:
          'Caisse qui penche, lames cassées par surcharge, chocs répétés.',
      mainOeuvreFcfa: 8000,
      pieceObligatoire: false,
      pieceCode: 'LAME_RESSORT',
      pieceLibelle: 'Lame de ressort / boudin d\'air',
      icone: Icons.airline_seat_recline_extra_rounded,
    ),
    SosPanne(
      code: 'HYDRAULIQUE_PL',
      libelle: 'Vérin de benne, hayon ou flexible hydraulique HS',
      description: 'Benne qui ne se lève plus, fuite d\'huile hydraulique.',
      mainOeuvreFcfa: 9000,
      pieceObligatoire: false,
      pieceCode: 'FLEXIBLE_HYDRAULIQUE',
      pieceLibelle: 'Flexible / pompe hydraulique',
      icone: Icons.plumbing_rounded,
    ),
  ];
}
