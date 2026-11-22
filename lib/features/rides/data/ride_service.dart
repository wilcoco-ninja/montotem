import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/core/offline/outbox_service.dart';
import 'package:montotem/features/rides/domain/ride_model.dart';

class RideException implements Exception {
  const RideException(this.message, {this.code});

  /// Message lisible, déjà en français.
  final String message;

  /// Code métier renvoyé par la base (ex. COURSE_EN_COURS), null si inconnu.
  final String? code;

  @override
  String toString() => message;
}

/// Courses (Zémidjan, Tricycle Fret) : tout passe par des fonctions SQL
/// sécurisées ; l'application ne modifie jamais la table directement.
class RideService {
  SupabaseClient get _sb => Supabase.instance.client;

  String? get currentUserId => _sb.auth.currentUser?.id;

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw RideException(_message(e), code: _code(e));
    } on RideException {
      rethrow;
    } catch (_) {
      throw const RideException(
          'Connexion impossible. Vérifiez votre réseau et réessayez.');
    }
  }

  /// Cree une demande de course et retourne son identifiant. Hors ligne :
  /// la demande est rangee dans l'outbox et envoyee au retour du reseau.
  Future<String> creer({
    required RideKind kind,
    required LatLng depart,
    required LatLng arrivee,
    required int tarifFcfa,
    required RidePaymentMethod paiement,
    String? adresseDepart,
    String? adresseArrivee,
  }) async {
    if (await OutboxService.reseauIndisponible()) {
      final reference = OutboxService.nouvelleReference('ride');
      await OutboxService.instance.enregistrer(
        kind: 'create_ride',
        clientRequestId: reference,
        payload: {
          'serviceKind': kind.code,
          'latDepart': depart.latitude,
          'lngDepart': depart.longitude,
          'latArrivee': arrivee.latitude,
          'lngArrivee': arrivee.longitude,
          'tarifFcfa': tarifFcfa,
          'paiement': paiement.code,
          'adresseDepart': adresseDepart,
          'adresseArrivee': adresseArrivee,
          'clientRequestId': reference,
        },
      );
      throw const RideException(
          'Hors ligne : votre demande est enregistrée. Elle sera envoyée '
          'automatiquement dès que le réseau revient.');
    }
    return _creerDirecte(
      kind: kind,
      depart: depart,
      arrivee: arrivee,
      tarifFcfa: tarifFcfa,
      paiement: paiement,
      adresseDepart: adresseDepart,
      adresseArrivee: adresseArrivee,
    );
  }

  Future<String> _creerDirecte({
    required RideKind kind,
    required LatLng depart,
    required LatLng arrivee,
    required int tarifFcfa,
    required RidePaymentMethod paiement,
    String? adresseDepart,
    String? adresseArrivee,
  }) =>
      _run(() async {
        final id = await _sb.rpc('create_ride', params: {
          'p_service_kind': kind.code,
          'p_pickup_lat': depart.latitude,
          'p_pickup_lng': depart.longitude,
          'p_dropoff_lat': arrivee.latitude,
          'p_dropoff_lng': arrivee.longitude,
          'p_fare_fcfa': tarifFcfa,
          'p_payment_method': paiement.code,
          'p_pickup_address': adresseDepart,
          'p_dropoff_address': adresseArrivee,
        });
        return '$id';
      });

  /// Rejoue une creation de course mise en file hors ligne.
  /// true : course creee. false : refus metier definitif du serveur (la
  /// tache est retiree). Exception : echec reseau transitoire (reessai).
  Future<bool> rejouerCreation(Map<String, dynamic> p) async {
    try {
      await _sb.rpc('create_ride', params: {
        'p_service_kind': p['serviceKind'],
        'p_pickup_lat': (p['latDepart'] as num).toDouble(),
        'p_pickup_lng': (p['lngDepart'] as num).toDouble(),
        'p_dropoff_lat': (p['latArrivee'] as num).toDouble(),
        'p_dropoff_lng': (p['lngArrivee'] as num).toDouble(),
        'p_fare_fcfa': (p['tarifFcfa'] as num).toInt(),
        'p_payment_method': p['paiement'],
        'p_pickup_address': p['adresseDepart'],
        'p_dropoff_address': p['adresseArrivee'],
      });
      return true;
    } on PostgrestException {
      return false;
    }
  }

  Future<Ride> details(String id) => _run(() async {
        final data = await _sb.rpc('ride_details', params: {'p_id': id});
        if (data is! Map) throw const RideException('Course introuvable.');
        return Ride.fromJson(Map<String, dynamic>.from(data));
      });

  /// Course non terminée du client connecté, ou null s'il n'en a aucune.
  Future<Ride?> courseActiveClient() async {
    final uid = currentUserId;
    final liste = await mesCourses();
    for (final r in liste) {
      if (r.clientId == uid && !r.status.termine) return r;
    }
    return null;
  }

  /// Historique du client ou du conducteur connecté (100 dernières courses).
  Future<List<Ride>> mesCourses() => _run(() async {
        final data = await _sb.rpc('my_rides');
        return (data as List)
            .whereType<Map>()
            .map((e) => Ride.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      });

  /// action : accept | arrived | start | complete | cancel.
  /// Retourne le nouveau statut.
  Future<String> action(
    String id,
    String action, {
    int? tarifFcfa,
    String? motif,
  }) =>
      _run(() async {
        final statut = await _sb.rpc('ride_action', params: {
          'p_ride': id,
          'p_action': action,
          'p_fare': tarifFcfa,
          'p_reason': motif,
        });
        return '$statut';
      });

  /// Envoie la position du conducteur ; retourne le statut courant.
  Future<String> envoyerPosition(String id, double lat, double lng) =>
      _run(() async {
        final statut = await _sb.rpc('update_ride_provider_position',
            params: {'p_ride': id, 'p_lat': lat, 'p_lng': lng});
        return '$statut';
      });

  /// Courses ouvertes autour du conducteur (vide s'il est bloqué).
  Future<List<NearbyRide>> proches({
    required double lat,
    required double lng,
    double rayonKm = 5,
  }) =>
      _run(() async {
        final data = await _sb.rpc('rides_nearby', params: {
          'p_lat': lat,
          'p_lng': lng,
          'p_radius_km': rayonKm,
        });
        return (data as List)
            .whereType<Map>()
            .map((e) => NearbyRide.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      });

  RealtimeChannel ecouterCourse(String id, void Function() onChange) {
    final canal = _sb.channel('ride-$id');
    canal
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rides',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: id,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
    return canal;
  }

  /// Toutes mes courses (la RLS filtre côté serveur).
  RealtimeChannel ecouterMesCourses(void Function() onChange) {
    final canal = _sb.channel('my-rides-${currentUserId ?? 'anon'}');
    canal
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rides',
          callback: (_) => onChange(),
        )
        .subscribe();
    return canal;
  }

  Future<void> arreter(RealtimeChannel canal) async {
    try {
      await _sb.removeChannel(canal);
    } catch (_) {}
  }

  static const List<String> _codes = [
    'NON_CONNECTE',
    'COURSE_EN_COURS',
    'WALLET_BLOQUE',
    'COMPTE_SUSPENDU',
    'PRESTATAIRE_NON_ACTIF',
    'SERVICE_INCOMPATIBLE',
    'MOMO_NON_CONFIGURE',
    'TROP_LOIN',
    'POSITION_INCONNUE',
    'POSITION_INVALIDE',
    'TARIF_INVALIDE',
    'PAIEMENT_INVALIDE',
    'SERVICE_INVALIDE',
    'STATUT_INVALIDE',
    'INTERDIT',
    'INTROUVABLE',
  ];

  String? _code(PostgrestException e) {
    for (final c in _codes) {
      if (e.message.contains(c)) return c;
    }
    return null;
  }

  String _message(PostgrestException e) {
    final m = e.message;
    if (m.contains('NON_CONNECTE')) return 'Session expirée. Reconnectez-vous.';
    if (m.contains('COURSE_EN_COURS')) {
      return 'Vous avez déjà une course en cours. Terminez-la ou annulez-la.';
    }
    if (m.contains('WALLET_BLOQUE')) {
      return 'Votre wallet est bloqué : rechargez-le pour accepter des courses.';
    }
    if (m.contains('COMPTE_SUSPENDU')) {
      return 'Votre compte est suspendu. Contactez le support MONTOTEM.';
    }
    if (m.contains('PRESTATAIRE_NON_ACTIF')) {
      return 'Votre compte doit être validé et votre abonnement actif.';
    }
    if (m.contains('SERVICE_INCOMPATIBLE')) {
      return 'Cette course ne correspond pas à votre type de service.';
    }
    if (m.contains('MOMO_NON_CONFIGURE')) {
      return 'Cette course est payée en Mobile Money : enregistrez d\'abord '
          'votre numéro de réception correspondant.';
    }
    if (m.contains('TROP_LOIN')) {
      return 'Rapprochez-vous du point de départ (moins de 500 m).';
    }
    if (m.contains('POSITION_INCONNUE')) {
      return 'Position GPS introuvable. Activez la localisation.';
    }
    if (m.contains('POSITION_INVALIDE')) return 'Position invalide.';
    if (m.contains('TARIF_INVALIDE')) {
      return 'Prix invalide (au maximum 50 % de plus que le prix convenu).';
    }
    if (m.contains('PAIEMENT_INVALIDE')) return 'Mode de paiement invalide.';
    if (m.contains('SERVICE_INVALIDE')) return 'Type de service invalide.';
    if (m.contains('STATUT_INVALIDE')) {
      return 'Cette action n\'est plus possible : la course a changé.';
    }
    if (m.contains('INTERDIT')) return 'Action non autorisée.';
    if (m.contains('INTROUVABLE')) return 'Course introuvable.';
    return 'Opération impossible. Réessayez.';
  }
}
