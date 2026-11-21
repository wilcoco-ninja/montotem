/// Constantes globales de configuration pour MONTOTEM.
class AppConstants {
  AppConstants._();

  static const String appName = 'MONTOTEM';

  // Position de repli (Cotonou) quand la géolocalisation échoue ou n'est
  // pas encore connue.
  static const double initialLatitude = 6.3703;
  static const double initialLongitude = 2.3912;

  static const double defaultZoom = 14.0;
  static const double defaultSearchRadiusKm = 10.0;

  // Valeurs alignées sur StatutContrat côté Django.
  static const String statusPending = 'pending';
  static const String statusAccepted = 'accepted';
  static const String statusArrived = 'arrived';
  static const String statusCompleted = 'completed';
  static const String statusCancelled = 'cancelled';
  static const String statusRefused = 'refused';

  /// Libellé français d'un statut (à utiliser à la place de `statut.value`
  /// dans les écrans : l'utilisateur ne doit pas voir "accepted").
  static String libelleStatut(String statut) => switch (statut) {
        statusPending => 'En attente',
        statusAccepted => 'Acceptée',
        statusArrived => 'Intervention en cours',
        statusCompleted => 'Terminée',
        statusCancelled => 'Annulée',
        statusRefused => 'Refusée',
        _ => statut,
      };
}
