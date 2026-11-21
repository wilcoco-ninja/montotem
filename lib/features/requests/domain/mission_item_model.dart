import 'package:flutter/foundation.dart';

/// Une prestation commandée, avec le prix figé au moment de la demande.
@immutable
class MissionItem {
  const MissionItem({
    required this.id,
    required this.nom,
    required this.prixFcfa,
  });

  final String id;
  final String nom;
  final int prixFcfa;

  factory MissionItem.fromJson(Map<String, dynamic> j) => MissionItem(
        id: '${j['id']}',
        nom: '${j['nom'] ?? ''}',
        prixFcfa: (j['prix_fcfa'] as num?)?.toInt() ?? 0,
      );
}
