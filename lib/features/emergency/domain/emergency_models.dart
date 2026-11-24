import 'package:flutter/material.dart';

/// Fiabilité des numéros d'un pays.
enum Confiance {
  officiel,
  recoupe,
  aConfirmer;

  static Confiance fromCode(String? c) => switch (c) {
    'officiel' => Confiance.officiel,
    'recoupe' => Confiance.recoupe,
    _ => Confiance.aConfirmer,
  };
}

/// Service de secours joignable par téléphone.
enum ServiceKind {
  police(
    'Police secours',
    'Commissariat / Police',
    Icons.local_police_rounded,
    Color(0xFF1565C0),
  ),
  fire(
    'Sapeurs-pompiers',
    'Caserne de sapeurs-pompiers',
    Icons.local_fire_department_rounded,
    Color(0xFFBF360C),
  ),
  ambulance(
    'Urgences / Ambulance',
    'Hôpital / Clinique',
    Icons.medical_services_rounded,
    Color(0xFF2E7D32),
  );

  const ServiceKind(this.libelle, this.libelleLieu, this.icone, this.couleur);

  final String libelle;
  final String libelleLieu;
  final IconData icone;
  final Color couleur;

  static ServiceKind? fromCode(String? code) {
    for (final k in ServiceKind.values) {
      if (k.name == code) return k;
    }
    return null;
  }
}

/// Situations proposées par le bouton SOS.
enum EmergencyType {
  accident(
    'Accident de la route',
    'Collision, véhicule renversé, blessés sur la route',
    Icons.car_crash_rounded,
    Color(0xFFC62828),
  ),
  fire(
    'Sapeurs-pompiers',
    'Incendie, fumée, fuite de gaz',
    Icons.local_fire_department_rounded,
    Color(0xFFBF360C),
  ),
  police(
    'Police secours',
    'Agression, vol, menace, danger',
    Icons.local_police_rounded,
    Color(0xFF1565C0),
  ),
  ambulance(
    'Urgences médicales',
    'Malaise, blessure, ambulance, hôpital',
    Icons.medical_services_rounded,
    Color(0xFF2E7D32),
  );

  const EmergencyType(this.libelle, this.description, this.icone, this.couleur);

  final String libelle;
  final String description;
  final IconData icone;
  final Color couleur;

  /// Service appelé quand l'utilisateur ne répond à aucune question.
  ServiceKind get serviceParDefaut => switch (this) {
    EmergencyType.accident => ServiceKind.ambulance,
    EmergencyType.fire => ServiceKind.fire,
    EmergencyType.police => ServiceKind.police,
    EmergencyType.ambulance => ServiceKind.ambulance,
  };
}

/// Numéros d'urgence d'un pays.
class CountryNumbers {
  const CountryNumbers({
    required this.code,
    required this.nom,
    required this.police,
    required this.fire,
    required this.ambulance,
    this.general,
    this.minLat,
    this.maxLat,
    this.minLng,
    this.maxLng,
    this.confiance = Confiance.aConfirmer,
  });

  final String code;
  final String nom;
  final String police;
  final String fire;
  final String ambulance;
  final String? general;
  final double? minLat;
  final double? maxLat;
  final double? minLng;
  final double? maxLng;
  final Confiance confiance;

  /// Dernier recours quand le pays est inconnu. Le 112 est redirigé vers le
  /// service local sur de nombreux réseaux, mais pas partout.
  static const CountryNumbers universel = CountryNumbers(
    code: '--',
    nom: 'Numéro international',
    police: '112',
    fire: '112',
    ambulance: '112',
    general: '112',
  );

  /// Le compte à rebours d'appel n'est lancé que pour des numéros officiels
  /// ou recoupés.
  bool get appelAutomatique => confiance != Confiance.aConfirmer;

  CountryNumbers avecConfiance(Confiance c) => CountryNumbers(
    code: code,
    nom: nom,
    police: police,
    fire: fire,
    ambulance: ambulance,
    general: general,
    minLat: minLat,
    maxLat: maxLat,
    minLng: minLng,
    maxLng: maxLng,
    confiance: c,
  );

  String numero(ServiceKind k) => switch (k) {
    ServiceKind.police => police,
    ServiceKind.fire => fire,
    ServiceKind.ambulance => ambulance,
  };

  bool contient(double lat, double lng) =>
      minLat != null &&
      maxLat != null &&
      minLng != null &&
      maxLng != null &&
      lat >= minLat! &&
      lat <= maxLat! &&
      lng >= minLng! &&
      lng <= maxLng!;

  double get surface =>
      (minLat == null || maxLat == null || minLng == null || maxLng == null)
      ? double.infinity
      : (maxLat! - minLat!) * (maxLng! - minLng!);

  factory CountryNumbers.fromJson(Map<String, dynamic> j) => CountryNumbers(
    code: '${j['country_code'] ?? ''}'.toUpperCase(),
    nom: '${j['country_name'] ?? ''}',
    police: '${j['police'] ?? '112'}',
    fire: '${j['fire'] ?? '112'}',
    ambulance: '${j['ambulance'] ?? '112'}',
    general: j['general'] as String?,
    minLat: (j['min_lat'] as num?)?.toDouble(),
    maxLat: (j['max_lat'] as num?)?.toDouble(),
    minLng: (j['min_lng'] as num?)?.toDouble(),
    maxLng: (j['max_lng'] as num?)?.toDouble(),
    confiance: Confiance.fromCode(j['confidence'] as String?),
  );
}

/// Pays retenu pour les secours. [candidats] contient plusieurs pays quand la
/// position GPS tombe dans la zone de plusieurs pays (frontière).
class ResolutionPays {
  const ResolutionPays(
    this.pays, {
    this.candidats = const [],
    this.choisi = false,
  });

  final CountryNumbers pays;
  final List<CountryNumbers> candidats;

  /// true quand l'utilisateur a choisi lui-même le pays.
  final bool choisi;

  bool get ambigu => candidats.length > 1;
}

enum Reponse { oui, non, nsp }

class SosQuestion {
  const SosQuestion(this.id, this.texte, {this.phraseOui, this.phraseNon});

  final String id;
  final String texte;

  /// Phrase à dire à l'opérateur selon la réponse.
  final String? phraseOui;
  final String? phraseNon;
}

const Map<EmergencyType, List<SosQuestion>> kQuestions = {
  EmergencyType.accident: [
    SosQuestion(
      'blesses',
      'Y a-t-il des blessés ?',
      phraseOui: 'Il y a des blessés.',
      phraseNon: 'Il n\'y a pas de blessés.',
    ),
    SosQuestion(
      'feu',
      'Y a-t-il du feu ou de la fumée ?',
      phraseOui: 'Il y a du feu ou de la fumée.',
    ),
    SosQuestion(
      'danger',
      'La route est-elle bloquée, ou y a-t-il un danger (carburant répandu, circulation) ?',
      phraseOui: 'La route est bloquée ou dangereuse.',
    ),
  ],
  EmergencyType.fire: [
    SosQuestion(
      'personnes',
      'Des personnes sont-elles en danger ou bloquées ?',
      phraseOui: 'Des personnes sont en danger ou bloquées.',
    ),
    SosQuestion(
      'gaz',
      'Sentez-vous du gaz, ou y a-t-il un risque d\'explosion ?',
      phraseOui: 'Il y a une odeur de gaz ou un risque d\'explosion.',
    ),
    SosQuestion(
      'blesses',
      'Y a-t-il des blessés ou des brûlés ?',
      phraseOui: 'Il y a des blessés ou des brûlés.',
    ),
  ],
  EmergencyType.police: [
    SosQuestion(
      'danger',
      'Êtes-vous en danger immédiat ?',
      phraseOui: 'Je suis en danger immédiat.',
    ),
    SosQuestion(
      'present',
      'L\'auteur est-il encore sur place ?',
      phraseOui: 'L\'auteur est encore sur place.',
      phraseNon: 'L\'auteur est parti.',
    ),
    SosQuestion(
      'blesses',
      'Y a-t-il des blessés ?',
      phraseOui: 'Il y a des blessés.',
    ),
  ],
  EmergencyType.ambulance: [
    SosQuestion(
      'respire',
      'La personne respire-t-elle ?',
      phraseNon: 'La personne ne respire pas.',
    ),
    SosQuestion(
      'consciente',
      'La personne est-elle consciente (répond-elle quand on lui parle) ?',
      phraseNon: 'La personne est inconsciente.',
    ),
    SosQuestion(
      'saigne',
      'Y a-t-il un saignement important ?',
      phraseOui: 'Il y a un saignement important.',
    ),
  ],
};

class SosPlan {
  const SosPlan({
    required this.principal,
    required this.secondaires,
    required this.aDire,
    this.consigne,
  });

  final ServiceKind principal;
  final List<ServiceKind> secondaires;
  final List<String> aDire;
  final String? consigne;

  /// Services utiles d'après les réponses. Simple indication : le client choisit.
  Set<ServiceKind> get suggeres => {principal, ...secondaires};
}

/// Décide quel service appeler d'après les réponses (les questions sans
/// réponse comptent comme « je ne sais pas »).
SosPlan evaluer(EmergencyType type, Map<String, Reponse> r) {
  bool oui(String id) => r[id] == Reponse.oui;
  bool non(String id) => r[id] == Reponse.non;

  final ServiceKind principal;
  final secondaires = <ServiceKind>[];
  String? consigne;

  switch (type) {
    case EmergencyType.accident:
      if (oui('feu')) {
        principal = ServiceKind.fire;
        if (!non('blesses')) secondaires.add(ServiceKind.ambulance);
        secondaires.add(ServiceKind.police);
      } else if (!non('blesses')) {
        principal = ServiceKind.ambulance;
        secondaires.add(ServiceKind.police);
      } else {
        principal = ServiceKind.police;
      }
      consigne =
          'Mettez-vous à l\'écart de la circulation si vous le pouvez. '
          'Ne déplacez pas les blessés sauf danger immédiat.';
    case EmergencyType.fire:
      principal = ServiceKind.fire;
      if (oui('blesses')) secondaires.add(ServiceKind.ambulance);
      consigne = oui('gaz')
          ? 'Éloignez-vous. N\'allumez rien et n\'actionnez aucun interrupteur.'
          : 'Éloignez-vous du danger. Ne retournez pas à l\'intérieur.';
    case EmergencyType.police:
      principal = ServiceKind.police;
      if (oui('blesses')) secondaires.add(ServiceKind.ambulance);
      if (oui('danger')) {
        consigne =
            'Mettez-vous en sécurité si possible et restez en ligne '
            'avec la police.';
      }
    case EmergencyType.ambulance:
      principal = ServiceKind.ambulance;
      consigne = non('respire')
          ? 'Dites tout de suite à l\'opérateur que la personne ne respire pas : '
                'il vous guidera.'
          : 'Restez auprès de la personne et gardez la ligne ouverte.';
  }

  final aDire = <String>['Il s\'agit de : ${type.libelle}.'];
  for (final q in kQuestions[type] ?? const <SosQuestion>[]) {
    final rep = r[q.id];
    if (rep == Reponse.oui && q.phraseOui != null) aDire.add(q.phraseOui!);
    if (rep == Reponse.non && q.phraseNon != null) aDire.add(q.phraseNon!);
  }

  return SosPlan(
    principal: principal,
    secondaires: secondaires,
    aDire: aDire,
    consigne: consigne,
  );
}
