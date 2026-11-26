import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/features/requests/domain/mission_payment_model.dart'
    show MomoAccount;

/// Format court d'une distance : « 350 m » ou « 2,4 km ».
String formaterDistance(int metres) => metres < 1000
    ? '$metres m'
    : '${(metres / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.tryParse('$v')?.toLocal();

/// Type de service de transport (valeur stockée dans rides.service_kind).
enum RideKind {
  zemidjan(
    'zemidjan',
    'Zémidjan',
    'Moto-taxi, 1 passager',
    Icons.two_wheeler_rounded,
  ),
  tricycleFret(
    'tricycle_fret',
    'Kloboto',
    'Transport de marchandises',
    Icons.local_shipping_rounded,
  ),
  tricyclePassagers(
    'tricycle_passenger',
    'Cloboto',
    'Tricycle, 2 à 3 passagers',
    Icons.electric_rickshaw_rounded,
  );

  const RideKind(this.code, this.libelle, this.description, this.icone);

  final String code;
  final String libelle;
  final String description;
  final IconData icone;

  static RideKind fromCode(String? c) => RideKind.values.firstWhere(
    (k) => k.code == c,
    orElse: () => RideKind.zemidjan,
  );
}

/// Mode de paiement d'une course. Le cash donne lieu à la commission de la
/// plateforme ; le Mobile Money se règle directement au conducteur.
enum RidePaymentMethod {
  cash('cash', 'Espèces'),
  mtn('mtn', 'MTN MoMo'),
  moov('moov', 'Moov Money'),
  celtiis('celtiis', 'Celtiis Cash');

  const RidePaymentMethod(this.code, this.libelle);

  final String code;
  final String libelle;

  bool get mobileMoney => this != RidePaymentMethod.cash;

  static RidePaymentMethod fromCode(String? c) => RidePaymentMethod.values
      .firstWhere((m) => m.code == c, orElse: () => RidePaymentMethod.cash);
}

enum RideStatus {
  requested,
  accepted,
  arrived,
  inProgress,
  verifying,
  completed,
  cancelled;

  static RideStatus fromValue(String? v) => switch (v) {
    'accepted' => RideStatus.accepted,
    'arrived' => RideStatus.arrived,
    'in_progress' => RideStatus.inProgress,
    'verifying' => RideStatus.verifying,
    'completed' => RideStatus.completed,
    'cancelled' => RideStatus.cancelled,
    _ => RideStatus.requested,
  };

  String get value => switch (this) {
    RideStatus.requested => 'requested',
    RideStatus.accepted => 'accepted',
    RideStatus.arrived => 'arrived',
    RideStatus.inProgress => 'in_progress',
    RideStatus.verifying => 'verifying',
    RideStatus.completed => 'completed',
    RideStatus.cancelled => 'cancelled',
  };

  String get libelle => switch (this) {
    RideStatus.requested => 'En attente d\'un conducteur',
    RideStatus.accepted => 'Conducteur en route',
    RideStatus.arrived => 'Conducteur arrivé',
    RideStatus.inProgress => 'Course en cours',
    RideStatus.verifying => 'Vérification de fin',
    RideStatus.completed => 'Terminée',
    RideStatus.cancelled => 'Annulée',
  };

  Color get couleur => switch (this) {
    RideStatus.requested => Colors.blueGrey,
    RideStatus.accepted => AppColors.navy,
    RideStatus.arrived => AppColors.amber,
    RideStatus.inProgress => AppColors.amber,
    RideStatus.verifying => AppColors.navy,
    RideStatus.completed => AppColors.success,
    RideStatus.cancelled => AppColors.emergency,
  };

  IconData get icone => switch (this) {
    RideStatus.requested => Icons.hourglass_top_rounded,
    RideStatus.accepted => Icons.directions_rounded,
    RideStatus.arrived => Icons.place_rounded,
    RideStatus.inProgress => Icons.navigation_rounded,
    RideStatus.verifying => Icons.pin_rounded,
    RideStatus.completed => Icons.check_circle_rounded,
    RideStatus.cancelled => Icons.cancel_rounded,
  };

  /// Conducteur attribué et course non terminée.
  bool get actif =>
      this == RideStatus.accepted ||
      this == RideStatus.arrived ||
      this == RideStatus.inProgress;

  bool get termine =>
      this == RideStatus.completed || this == RideStatus.cancelled;
}

@immutable
class Ride {
  const Ride({
    required this.id,
    required this.status,
    required this.kind,
    required this.payment,
    required this.clientId,
    required this.fareFcfa,
    required this.distanceM,
    required this.pickup,
    required this.dropoff,
    required this.createdAt,
    required this.clientName,
    this.providerId,
    this.finalFareFcfa,
    this.commissionFcfa,
    this.otpCode,
    this.otpExpiresAt,
    this.pickupAddress,
    this.dropoffAddress,
    this.providerPoint,
    this.providerPosAt,
    this.acceptedAt,
    this.arrivedAt,
    this.startedAt,
    this.completedAt,
    this.cancelledAt,
    this.cancelReason,
    this.providerName,
    this.clientPhone,
    this.providerPhone,
    this.providerMomo,
  });

  factory Ride.fromJson(Map<String, dynamic> j) {
    final plat = (j['provider_lat'] as num?)?.toDouble();
    final plng = (j['provider_lng'] as num?)?.toDouble();
    return Ride(
      id: '${j['id']}',
      status: RideStatus.fromValue(j['status'] as String?),
      kind: RideKind.fromCode(j['service_kind'] as String?),
      payment: RidePaymentMethod.fromCode(j['payment_method'] as String?),
      clientId: '${j['client_id']}',
      providerId: j['provider_id'] == null ? null : '${j['provider_id']}',
      fareFcfa: (j['fare_fcfa'] as num?)?.toInt() ?? 0,
      finalFareFcfa: (j['final_fare_fcfa'] as num?)?.toInt(),
      commissionFcfa: (j['commission_fcfa'] as num?)?.toInt(),
      otpCode: j['otp_code'] as String?,
      otpExpiresAt: _date(j['otp_expires_at']),
      distanceM: (j['distance_m'] as num?)?.toInt() ?? 0,
      pickup: LatLng(
        (j['pickup_lat'] as num).toDouble(),
        (j['pickup_lng'] as num).toDouble(),
      ),
      dropoff: LatLng(
        (j['dropoff_lat'] as num).toDouble(),
        (j['dropoff_lng'] as num).toDouble(),
      ),
      pickupAddress: j['pickup_address'] as String?,
      dropoffAddress: j['dropoff_address'] as String?,
      providerPoint: (plat != null && plng != null) ? LatLng(plat, plng) : null,
      providerPosAt: _date(j['provider_pos_at']),
      acceptedAt: _date(j['accepted_at']),
      arrivedAt: _date(j['arrived_at']),
      startedAt: _date(j['started_at']),
      completedAt: _date(j['completed_at']),
      cancelledAt: _date(j['cancelled_at']),
      cancelReason: j['cancel_reason'] as String?,
      createdAt: _date(j['created_at']) ?? DateTime.now(),
      clientName: (j['client_name'] as String?) ?? 'Client',
      providerName: j['provider_name'] as String?,
      clientPhone: j['client_phone'] as String?,
      providerPhone: j['provider_phone'] as String?,
      providerMomo: j['provider_momo'] is Map
          ? MomoAccount.fromJson(
              Map<String, dynamic>.from(j['provider_momo'] as Map),
            )
          : null,
    );
  }

  final String id;
  final RideStatus status;
  final RideKind kind;
  final RidePaymentMethod payment;
  final String clientId;
  final String? providerId;
  final int fareFcfa;
  final int? finalFareFcfa;

  /// Visible uniquement du conducteur concerné (jamais du client).
  final int? commissionFcfa;

  /// Code de fin de course : visible uniquement du client, statut verifying.
  final String? otpCode;
  final DateTime? otpExpiresAt;
  final int distanceM;
  final LatLng pickup;
  final LatLng dropoff;
  final String? pickupAddress;
  final String? dropoffAddress;
  final LatLng? providerPoint;
  final DateTime? providerPosAt;
  final DateTime? acceptedAt;
  final DateTime? arrivedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final DateTime createdAt;
  final String clientName;
  final String? providerName;
  final String? clientPhone;
  final String? providerPhone;
  final MomoAccount? providerMomo;

  /// Prix réellement dû : le prix final une fois la course terminée.
  int get prixFcfa => finalFareFcfa ?? fareFcfa;

  String get distanceLibelle => formaterDistance(distanceM);

  /// Commission estimée pour un pourcentage donné (course cash uniquement).
  int commissionEstimee(int pourcentage) => payment == RidePaymentMethod.cash
      ? (prixFcfa * pourcentage / 100).round()
      : 0;
}

/// Une course ouverte proposée à un conducteur (RPC rides_nearby).
@immutable
class NearbyRide {
  const NearbyRide({
    required this.id,
    required this.kind,
    required this.fareFcfa,
    required this.payment,
    required this.distanceToPickupM,
    required this.tripDistanceM,
    required this.createdAt,
    this.pickupAddress,
    this.dropoffAddress,
  });

  factory NearbyRide.fromJson(Map<String, dynamic> j) => NearbyRide(
    id: '${j['id']}',
    kind: RideKind.fromCode(j['service_kind'] as String?),
    fareFcfa: (j['fare_fcfa'] as num?)?.toInt() ?? 0,
    payment: RidePaymentMethod.fromCode(j['payment_method'] as String?),
    distanceToPickupM: (j['distance_to_pickup_m'] as num?)?.toInt() ?? 0,
    tripDistanceM: (j['trip_distance_m'] as num?)?.toInt() ?? 0,
    createdAt: _date(j['created_at']) ?? DateTime.now(),
    pickupAddress: j['pickup_address'] as String?,
    dropoffAddress: j['dropoff_address'] as String?,
  );

  final String id;
  final RideKind kind;
  final int fareFcfa;
  final RidePaymentMethod payment;
  final int distanceToPickupM;
  final int tripDistanceM;
  final DateTime createdAt;
  final String? pickupAddress;
  final String? dropoffAddress;
}
