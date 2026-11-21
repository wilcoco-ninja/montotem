import 'package:flutter/material.dart';

/// Icône représentative du métier — centralisée ici pour rester cohérente
/// partout dans l'app (accueil carte, liste de recherche...).
IconData iconePourMetier(String metier) {
  final m = metier.toLowerCase();
  if (m.contains('vulcanis') || m.contains('pneu')) {
    return Icons.donut_large_outlined;
  }
  if (m.contains('électric') || m.contains('electric')) {
    return Icons.electrical_services_outlined;
  }
  if (m.contains('essence') || m.contains('station')) {
    return Icons.local_gas_station_outlined;
  }
  if (m.contains('garage')) {
    return Icons.garage_outlined;
  }
  return Icons.build_outlined; // mécanicien par défaut
}

/// Représente un prestataire de service (dépanneur, plombier, électricien...).
class Prestataire {
  final String id;
  final String nom;
  final String metier;
  final double latitude;
  final double longitude;
  final double noteMoyenne;
  final bool disponible;
  final String? telephone;
  final String? photoUrl;

  /// Nature du prestataire (providers.provider_kind) : 'zemidjan',
  /// 'tricycle_fret' (Kloboto) ou autre = dépanneur. Peut être absent.
  final String? kind;

  /// Identité commerciale — affichée aux clients pour identifier
  /// facilement le garage/atelier.
  final String? businessName;
  final String? adresse;

  final String? statutMission;
  final bool verifie;
  final DateTime? finAbonnement;
  final int missionsCompletees;
  final int missionsRefusees;
  final int clientsSatisfaits;
  final int clientsInsatisfaits;
  final int? pointsBruts;

  const Prestataire({
    required this.id,
    required this.nom,
    required this.metier,
    required this.latitude,
    required this.longitude,
    this.noteMoyenne = 0.0,
    this.disponible = false,
    this.telephone,
    this.photoUrl,
    this.kind,
    this.businessName,
    this.adresse,
    this.statutMission,
    this.verifie = false,
    this.finAbonnement,
    this.missionsCompletees = 0,
    this.missionsRefusees = 0,
    this.clientsSatisfaits = 0,
    this.clientsInsatisfaits = 0,
    this.pointsBruts,
  });

  String get nomAffiche =>
      (businessName != null && businessName!.trim().isNotEmpty)
          ? businessName!
          : nom;

  int get points =>
      pointsBruts ?? ((noteMoyenne * 100).round() + (missionsCompletees * 5));

  int? get joursAbonnementRestants {
    if (finAbonnement == null) return null;
    final diff = finAbonnement!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  bool get abonnementExpire =>
      finAbonnement != null && finAbonnement!.isBefore(DateTime.now());

  factory Prestataire.fromJson(Map<String, dynamic> json) {
    return Prestataire(
      id: json['id']?.toString() ?? '',
      nom: json['nom'] as String? ?? json['name'] as String? ?? 'Prestataire',
      metier:
          json['metier'] as String? ?? json['job'] as String? ?? 'Non spécifié',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      noteMoyenne:
          (json['note_moyenne'] as num?)?.toDouble() ??
          (json['rating'] as num?)?.toDouble() ??
          0.0,
      disponible:
          json['disponible'] as bool? ?? json['available'] as bool? ?? false,
      telephone: json['telephone'] as String? ?? json['phone'] as String?,
      photoUrl:
          json['photo_url'] as String? ?? json['photo_profil_url'] as String?,
      kind: json['provider_kind'] as String? ?? json['kind'] as String?,
      businessName:
          json['business_name'] as String? ?? json['nom_garage'] as String?,
      adresse: json['adresse'] as String? ?? json['ville'] as String?,
      statutMission: json['statut_mission'] as String?,
      verifie:
          json['verifie'] as bool? ?? json['is_verified'] as bool? ?? false,
      finAbonnement: json['fin_abonnement'] != null
          ? DateTime.tryParse(json['fin_abonnement'].toString())
          : null,
      missionsCompletees: (json['missions_completees'] as num?)?.toInt() ?? 0,
      missionsRefusees: (json['missions_refusees'] as num?)?.toInt() ?? 0,
      clientsSatisfaits: (json['clients_satisfaits'] as num?)?.toInt() ?? 0,
      clientsInsatisfaits: (json['clients_insatisfaits'] as num?)?.toInt() ?? 0,
      pointsBruts: (json['points'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'nom': nom,
    'metier': metier,
    'latitude': latitude,
    'longitude': longitude,
    'note_moyenne': noteMoyenne,
    'disponible': disponible,
    if (telephone != null) 'telephone': telephone,
    if (photoUrl != null) 'photo_url': photoUrl,
    if (kind != null) 'provider_kind': kind,
    if (businessName != null) 'business_name': businessName,
    if (adresse != null) 'adresse': adresse,
    if (statutMission != null) 'statut_mission': statutMission,
    'verifie': verifie,
    if (finAbonnement != null)
      'fin_abonnement': finAbonnement!.toIso8601String(),
    'missions_completees': missionsCompletees,
    'missions_refusees': missionsRefusees,
    'clients_satisfaits': clientsSatisfaits,
    'clients_insatisfaits': clientsInsatisfaits,
    if (pointsBruts != null) 'points': pointsBruts,
  };
}