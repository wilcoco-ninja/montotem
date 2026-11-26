import 'package:flutter/material.dart';

/// Métiers du dépannage (prestations, déplacement, carte des dépanneurs).
const List<String> kMetiersDepannage = [
  'Mécanicien',
  'Vulcanisateur pneu',
  'Électricien auto & moto',
  'Station d\'essence',
  'Service garage',
  'Dépanneuse / Remorquage',
  'Vendeur de carburant',
  'Lavage auto & moto',
  'Soudeur / Châssis',
  'Mécatronicien (diagnostic auto)',
  'Diéséliste (injection)',
  'Tôlier-Peintre',
  'Hydraulicien PL',
];

/// Métiers du transport (courses). Le libellé détermine provider_kind côté
/// serveur (trigger providers_default_kind) : « Zémidjan » → zemidjan,
/// « Tricycle Passagers » → tricycle_passenger,
/// « Tricycle Fret » → tricycle_fret. Ne pas modifier ces libellés sans
/// adapter provider_kind_from_metier().
const List<String> kMetiersTransport = [
  'Zémidjan',
  'Tricycle Passagers',
  'Tricycle Fret',
];

const List<String> kTousMetiers = [...kMetiersDepannage, ...kMetiersTransport];

const Map<String, IconData> kIconesMetier = {
  'Mécanicien': Icons.build_outlined,
  'Vulcanisateur pneu': Icons.donut_large_outlined,
  'Électricien auto & moto': Icons.electrical_services_outlined,
  'Station d\'essence': Icons.local_gas_station_outlined,
  'Service garage': Icons.garage_outlined,
  'Dépanneuse / Remorquage': Icons.local_shipping_rounded,
  'Vendeur de carburant': Icons.local_gas_station_rounded,
  'Lavage auto & moto': Icons.local_car_wash_rounded,
  'Soudeur / Châssis': Icons.construction_rounded,
  'Mécatronicien (diagnostic auto)': Icons.memory_rounded,
  'Diéséliste (injection)': Icons.oil_barrel_outlined,
  'Tôlier-Peintre': Icons.format_paint_rounded,
  'Hydraulicien PL': Icons.plumbing_rounded,
  'Zémidjan': Icons.two_wheeler_rounded,
  'Tricycle Passagers': Icons.electric_rickshaw_rounded,
  'Tricycle Fret': Icons.local_shipping_rounded,
};

bool estMetierTransport(String? metier) =>
    metier != null && kMetiersTransport.contains(metier);
