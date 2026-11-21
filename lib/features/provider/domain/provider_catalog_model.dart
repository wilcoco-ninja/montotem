import 'package:flutter/material.dart';

/// Univers de véhicules gérés. Clé = valeur stockée en base
/// (providers.vehicle_types / provider_catalog_items.categorie_vehicule).
const Map<String, ({String label, IconData icon, String detail})> kVehicules = {
  'moto': (
    label: 'Moto',
    icon: Icons.two_wheeler_rounded,
    detail: 'Motos et cyclomoteurs',
  ),
  'voiture': (
    label: 'Auto',
    icon: Icons.directions_car_rounded,
    detail: 'Véhicules légers',
  ),
  'camion': (
    label: 'Camion',
    icon: Icons.local_shipping_rounded,
    detail: 'Poids lourds',
  ),
};

/// Prestations express proposées en un geste, par univers de véhicule.
const Map<String, List<String>> kServicesExpress = {
  'moto': [
    'Crevaison (chambre à air)',
    'Crevaison (tubeless)',
    'Panne d\'essence',
    'Batterie 12 V moto',
    'Câble ou chaîne',
  ],
  'voiture': [
    'Boost / changement de batterie',
    'Changement de roue',
    'Mécanique rapide',
    'Diagnostic OBD2',
    'Déblocage de frein',
  ],
  'camion': [
    'Pneumatique poids lourd',
    'Circuit d\'air comprimé / freinage',
    'Flexible hydraulique',
    'Panne de carburant / durites',
  ],
};

/// Compétences suggérées (texte libre : 2 à 60 caractères, 30 maximum).
const List<String> kCompetencesSuggerees = [
  'Diagnostic électronique',
  'Climatisation auto',
  'Freinage',
  'Changement d\'huile',
  'Démarrage / alternateur',
  'Soudure',
  'Remorquage',
  'Dépannage poids lourd',
];

const int kCompetenceMin = 2;
const int kCompetenceMax = 60;
const int kCompetencesMaxParPrestataire = 30;

/// Une prestation du catalogue d'un prestataire : UN prix fixe, jamais de devis.
@immutable
class ServiceTarif {
  const ServiceTarif({
    this.id,
    required this.nom,
    required this.categorieVehicule,
    required this.prixFcfa,
  });

  /// Identifiant en base (absent tant que la prestation n'est pas enregistrée).
  final String? id;
  final String nom;
  final String categorieVehicule; // moto | voiture | camion
  final int prixFcfa;

  factory ServiceTarif.fromJson(Map<String, dynamic> j) => ServiceTarif(
        id: j['id'] == null ? null : '${j['id']}',
        nom: '${j['nom'] ?? ''}',
        categorieVehicule: '${j['categorie_vehicule'] ?? 'voiture'}',
        prixFcfa: (j['prix_fcfa'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'nom': nom,
        'categorie_vehicule': categorieVehicule,
        'prix_fcfa': prixFcfa,
      };

  @override
  bool operator ==(Object other) =>
      other is ServiceTarif &&
      other.id == id &&
      other.nom == nom &&
      other.categorieVehicule == categorieVehicule &&
      other.prixFcfa == prixFcfa;

  @override
  int get hashCode => Object.hash(id, nom, categorieVehicule, prixFcfa);
}

/// Fiche publique d'un prestataire : prestations à prix fixe, compétences,
/// paramètres de déplacement et capacité à encaisser en Mobile Money.
@immutable
class ProviderPublicCatalog {
  const ProviderPublicCatalog({
    required this.vehicleTypes,
    required this.skills,
    required this.tarifKmFcfa,
    required this.fraisMinFcfa,
    required this.rayonMaxKm,
    required this.services,
    this.accepteMobileMoney = false,
    this.idDocumentType,
    this.photoGarageUrl,
    this.garageDescription,
  });

  final List<String> vehicleTypes;
  final List<String> skills;
  final int tarifKmFcfa;
  final int fraisMinFcfa;
  final int rayonMaxKm;
  final List<ServiceTarif> services;
  final bool accepteMobileMoney;
  final String? idDocumentType;
  final String? photoGarageUrl;
  final String? garageDescription;

  List<ServiceTarif> servicesPour(String vehicule) =>
      services.where((s) => s.categorieVehicule == vehicule).toList();

  factory ProviderPublicCatalog.fromJson(Map<String, dynamic> j) =>
      ProviderPublicCatalog(
        vehicleTypes:
            (j['vehicle_types'] as List?)?.map((e) => '$e').toList() ??
                const [],
        skills: (j['skills'] as List?)?.map((e) => '$e').toList() ?? const [],
        tarifKmFcfa: (j['tarif_km_fcfa'] as num?)?.toInt() ?? 0,
        fraisMinFcfa: (j['frais_deplacement_min_fcfa'] as num?)?.toInt() ?? 0,
        rayonMaxKm: (j['rayon_max_km'] as num?)?.toInt() ?? 15,
        accepteMobileMoney: j['accepte_mobile_money'] == true,
        services: (j['services'] as List?)
                ?.whereType<Map>()
                .map((e) => ServiceTarif.fromJson(Map<String, dynamic>.from(e)))
                .where((s) => s.prixFcfa > 0)
                .toList() ??
            const [],
        idDocumentType: j['id_document_type'] as String?,
        photoGarageUrl: j['photo_garage_url'] as String?,
        garageDescription: j['garage_description'] as String?,
      );
}
