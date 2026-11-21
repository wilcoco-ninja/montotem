import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/features/requests/domain/mission_payment_model.dart';

enum MissionStatus {
  pending,
  accepted,
  arrived,
  working,
  completed,
  cancelled,
  refused;

  static MissionStatus fromValue(String? v) => MissionStatus.values.firstWhere(
        (s) => s.name == v,
        orElse: () => MissionStatus.pending,
      );

  String get value => name;

  String get libelle => switch (this) {
        MissionStatus.pending => 'En attente de réponse',
        MissionStatus.accepted => 'Le dépanneur est en route',
        MissionStatus.arrived => 'Le dépanneur est arrivé',
        MissionStatus.working => 'Réparation en cours',
        MissionStatus.completed => 'Terminée',
        MissionStatus.cancelled => 'Annulée',
        MissionStatus.refused => 'Refusée',
      };

  Color get couleur => switch (this) {
        MissionStatus.pending => Colors.blueGrey,
        MissionStatus.accepted => AppColors.navy,
        MissionStatus.arrived => AppColors.amber,
        MissionStatus.working => AppColors.amber,
        MissionStatus.completed => AppColors.success,
        MissionStatus.cancelled => AppColors.emergency,
        MissionStatus.refused => AppColors.emergency,
      };

  IconData get icone => switch (this) {
        MissionStatus.pending => Icons.hourglass_top_rounded,
        MissionStatus.accepted => Icons.directions_car_rounded,
        MissionStatus.arrived => Icons.place_rounded,
        MissionStatus.working => Icons.build_circle_rounded,
        MissionStatus.completed => Icons.check_circle_rounded,
        MissionStatus.cancelled => Icons.cancel_rounded,
        MissionStatus.refused => Icons.cancel_rounded,
      };

  bool get actif =>
      this == MissionStatus.accepted ||
      this == MissionStatus.arrived ||
      this == MissionStatus.working;

  bool get termine =>
      this == MissionStatus.completed ||
      this == MissionStatus.cancelled ||
      this == MissionStatus.refused;
}

DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.tryParse('$v')?.toLocal();

@immutable
class Mission {
  const Mission({
    required this.id,
    required this.status,
    required this.vehicleType,
    required this.problem,
    required this.clientId,
    required this.providerId,
    required this.clientPoint,
    required this.distanceKm,
    required this.travelFeeFcfa,
    required this.repairFeeFcfa,
    required this.paidFcfa,
    required this.createdAt,
    required this.clientName,
    required this.providerName,
    required this.reviewed,
    this.description,
    this.clientAddress,
    this.providerPoint,
    this.providerPosAt,
    this.acceptedAt,
    this.arrivedAt,
    this.workStartedAt,
    this.workEndedAt,
    this.clientPhone,
    this.providerPhone,
    this.providerMomo,
  });

  final String id;
  final MissionStatus status;
  final String vehicleType;
  final String problem;
  final String? description;
  final String clientId;
  final String providerId;
  final LatLng clientPoint;
  final String? clientAddress;
  final LatLng? providerPoint;
  final DateTime? providerPosAt;
  final double distanceKm;
  final int travelFeeFcfa;
  final int repairFeeFcfa;
  final int paidFcfa;
  final DateTime? acceptedAt;
  final DateTime? arrivedAt;
  final DateTime? workStartedAt;
  final DateTime? workEndedAt;
  final DateTime createdAt;
  final String clientName;
  final String providerName;
  final String? clientPhone;
  final String? providerPhone;
  final MomoAccount? providerMomo;
  final bool reviewed;

  int get totalFcfa => travelFeeFcfa + repairFeeFcfa;

  /// Reste à payer, jamais négatif.
  int get resteFcfa {
    final reste = totalFcfa - paidFcfa;
    return reste < 0 ? 0 : reste;
  }

  Duration? get dureeTravail {
    final start = workStartedAt;
    if (start == null) return null;
    return (workEndedAt ?? DateTime.now()).difference(start);
  }

  factory Mission.fromJson(Map<String, dynamic> j) {
    final plat = (j['provider_lat'] as num?)?.toDouble();
    final plng = (j['provider_lng'] as num?)?.toDouble();
    return Mission(
      id: '${j['id']}',
      status: MissionStatus.fromValue(j['status'] as String?),
      vehicleType: '${j['vehicle_type'] ?? 'voiture'}',
      problem: '${j['problem'] ?? ''}',
      description: j['description'] as String?,
      clientId: '${j['client_id']}',
      providerId: '${j['provider_id']}',
      clientPoint: LatLng(
        (j['client_lat'] as num).toDouble(),
        (j['client_lng'] as num).toDouble(),
      ),
      clientAddress: j['client_address'] as String?,
      providerPoint: (plat != null && plng != null) ? LatLng(plat, plng) : null,
      providerPosAt: _date(j['provider_pos_at']),
      distanceKm: (j['distance_km'] as num?)?.toDouble() ?? 0,
      travelFeeFcfa: (j['travel_fee_fcfa'] as num?)?.toInt() ?? 0,
      repairFeeFcfa: (j['repair_fee_fcfa'] as num?)?.toInt() ?? 0,
      paidFcfa: (j['paid_fcfa'] as num?)?.toInt() ?? 0,
      acceptedAt: _date(j['accepted_at']),
      arrivedAt: _date(j['arrived_at']),
      workStartedAt: _date(j['work_started_at']),
      workEndedAt: _date(j['work_ended_at']),
      createdAt: _date(j['created_at']) ?? DateTime.now(),
      clientName: (j['client_name'] as String?) ?? 'Client',
      providerName: (j['provider_name'] as String?) ?? 'Prestataire',
      clientPhone: j['client_phone'] as String?,
      providerPhone: j['provider_phone'] as String?,
      providerMomo: j['provider_momo'] is Map
          ? MomoAccount.fromJson(
              Map<String, dynamic>.from(j['provider_momo'] as Map))
          : null,
      reviewed: j['reviewed'] == true,
    );
  }
}