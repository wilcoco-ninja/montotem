import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:url_launcher/url_launcher.dart';

import 'package:montotem/core/utils/responsive.dart';
import 'package:montotem/core/utils/travel_fee.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/requests/data/mission_service.dart';
import 'package:montotem/features/requests/domain/mission_model.dart';
import 'package:montotem/features/requests/presentation/mission_chat_sheet.dart';
import 'package:montotem/features/requests/presentation/widgets/mission_payments_card.dart';
import 'package:montotem/features/requests/presentation/widgets/report_provider_sheet.dart';

class ClientRequestDetailScreen extends StatefulWidget {
  const ClientRequestDetailScreen({super.key, required this.requestId});
  final String requestId;

  @override
  State<ClientRequestDetailScreen> createState() =>
      _ClientRequestDetailScreenState();
}

class _ClientRequestDetailScreenState extends State<ClientRequestDetailScreen> {
  static const Distance _distance = Distance();

  final MissionService _service = MissionService();
  final TextEditingController _commentaire = TextEditingController();
  RealtimeChannel? _canal;

  Mission? _m;
  bool _loading = true;
  String? _error;
  bool _envoiAvis = false;
  int _etoiles = 5;
  int? _pointsGagnes;

  @override
  void initState() {
    super.initState();
    _charger();
    _canal = _service.ecouterMission(widget.requestId, () {
      if (mounted) _charger(silencieux: true);
    });
  }

  @override
  void dispose() {
    _commentaire.dispose();
    final c = _canal;
    if (c != null) _service.arreter(c);
    super.dispose();
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _charger({bool silencieux = false}) async {
    if (!silencieux) setState(() => _loading = true);
    try {
      final m = await _service.obtenir(widget.requestId);
      if (mounted) {
        setState(() {
          _m = m;
          _error = null;
        });
      }
    } on MissionException catch (e) {
      if (mounted && _m == null) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _appeler(String? phone) async {
    final tel = phone?.replaceAll(RegExp(r'[^\d+]'), '');
    if (tel == null || tel.isEmpty) {
      _msg('Numéro pas encore disponible.');
      return;
    }
    try {
      await launchUrl(Uri(scheme: 'tel', path: tel));
    } catch (_) {
      if (mounted) _msg('Impossible de lancer l\'appel.');
    }
  }

  Future<void> _annuler() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler la demande ?'),
        content: const Text(
          'Le dépanneur sera prévenu.',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non, garder'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Oui, annuler'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.annuler(widget.requestId, motif: 'Annulée par le client');
      await _charger(silencieux: true);
    } on MissionException catch (e) {
      if (mounted) _msg(e.message);
    }
  }

  Future<void> _envoyerAvis() async {
    setState(() => _envoiAvis = true);
    try {
      final pts = await _service.laisserAvis(
        widget.requestId,
        _etoiles,
        _commentaire.text.trim().isEmpty ? null : _commentaire.text.trim(),
      );
      if (!mounted) return;
      setState(() => _pointsGagnes = pts);
      await _charger(silencieux: true);
    } on MissionException catch (e) {
      if (mounted) _msg(e.message);
    } finally {
      if (mounted) setState(() => _envoiAvis = false);
    }
  }

  // ✅ CORRECTION 1 : `final scheme` SUPPRIMÉ (inutilisé dans build())
  @override
  Widget build(BuildContext context) {
    final m = _m;
    return Scaffold(
      appBar: AppBar(title: const Text('Suivi de ma demande')),
      body: _loading && m == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && m == null
          ? Center(
              child: SingleChildScrollView(
                child: ErrorState(message: _error!, onRetry: _charger),
              ),
            )
          : m == null
          ? const SizedBox.shrink()
          : _contenu(m),
    );
  }

  Widget _contenu(Mission m) {
    return RefreshIndicator(
      onRefresh: _charger,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gutter = context.gutter;
          if (constraints.maxWidth >= 900) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(gutter, 8, gutter / 2, 32),
                    children: _blocSuivi(m, hauteurCarte: 340),
                  ),
                ),
                Expanded(
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(gutter / 2, 8, gutter, 32),
                    children: _blocActions(m),
                  ),
                ),
              ],
            );
          }
          return ContentWidth(
            maxWidth: 720,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
              children: [
                ..._blocSuivi(m, hauteurCarte: 240),
                ..._blocActions(m),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _blocSuivi(Mission m, {required double hauteurCarte}) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.8);
    final prov = m.providerPoint;
    final distKm = prov == null
        ? null
        : _distance.as(LengthUnit.Kilometer, prov, m.clientPoint);
    final eta = distKm == null ? null : (distKm * 1.25 / 25 * 60).ceil();
    return [
      SoftCard(
        child: Row(
          children: [
            Icon(m.status.icone, color: m.status.couleur, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.status.libelle,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    m.providerName,
                    style: TextStyle(fontSize: 16, color: muted),
                  ),
                  if (m.status == MissionStatus.accepted && eta != null)
                    Text(
                      'Arrivée estimée : environ $eta min',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (m.status.actif) ...[
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: hauteurCarte,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: m.clientPoint,
                initialZoom: 14.5,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'bj.totem.app',
                ),
                if (prov != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [prov, m.clientPoint],
                        color: scheme.primary,
                        strokeWidth: 4,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: m.clientPoint,
                      width: 44,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: Icon(
                        Icons.location_on,
                        size: 42,
                        color: scheme.error,
                      ),
                    ),
                    if (prov != null)
                      Marker(
                        point: prov,
                        width: 46,
                        height: 46,
                        child: Container(
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                          child: const Icon(
                            Icons.build_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
      const SectionTitle('Déroulement'),
      _Etapes(status: m.status),
    ];
  }

  // ✅ CORRECTION 2 : `final scheme` AJOUTÉ en première ligne
  List<Widget> _blocActions(Mission m) {
    final scheme = Theme.of(context).colorScheme;
    return [
      const SectionTitle('Détails'),
      SoftCard(
        child: Column(
          children: [
            InfoRow(
              icon: Icons.build_outlined,
              label: 'Problème',
              value: m.problem,
            ),
            InfoRow(
              icon: Icons.payments_outlined,
              label: 'Frais de déplacement',
              value: TravelFee.fcfa(m.travelFeeFcfa),
            ),
            if (m.status == MissionStatus.completed)
              InfoRow(
                icon: Icons.receipt_long_outlined,
                label: 'Total à régler',
                value: TravelFee.fcfa(m.totalFcfa),
              ),
          ],
        ),
      ),
      if (m.status.actif || m.status == MissionStatus.completed) ...[
        const SectionTitle('Paiements'),
        MissionPaymentsCard(mission: m, asClient: true),
      ],
      const SizedBox(height: 14),
      if (m.status.actif) ...[
        AppButton(
          label: 'Appeler le dépanneur',
          icon: Icons.call_rounded,
          onPressed: () => _appeler(m.providerPhone),
        ),
        const SizedBox(height: 8),
        AppButton(
          label: 'Écrire un message',
          icon: Icons.chat_bubble_outline_rounded,
          variant: AppButtonVariant.secondary,
          onPressed: () => showMissionChatSheet(context, m.id),
        ),
      ],
      if (m.status == MissionStatus.pending ||
          m.status == MissionStatus.accepted)
        AppButton(
          label: 'Annuler la demande',
          variant: AppButtonVariant.text,
          onPressed: _annuler,
        ),
      if (m.status == MissionStatus.completed && !m.reviewed) ...[
        const SectionTitle('Votre avis'),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Donnez une note et gagnez des points d\'étoiles.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final v = i + 1;
                  return IconButton(
                    iconSize: 44,
                    tooltip: '$v étoile${v > 1 ? 's' : ''}',
                    icon: Icon(
                      v <= _etoiles
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: Colors.amber.shade700,
                    ),
                    onPressed: () => setState(() => _etoiles = v),
                  );
                }),
              ),
              AppTextField(
                label: 'Commentaire (20 caractères = 5 points bonus)',
                icon: Icons.chat_bubble_outline_rounded,
                controller: _commentaire,
                maxLines: 3,
                maxLength: 500,
              ),
              const SizedBox(height: 12),
              AppButton(
                label: 'Envoyer mon avis',
                icon: Icons.send_rounded,
                loading: _envoiAvis,
                onPressed: _envoyerAvis,
              ),
            ],
          ),
        ),
      ],
      if (_pointsGagnes != null ||
          (m.reviewed && m.status == MissionStatus.completed))
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Center(
            child: StatusPill(
              label: _pointsGagnes != null
                  ? 'Merci ! +$_pointsGagnes points d\'étoiles'
                  : 'Avis envoyé, merci !',
              color: scheme.secondary,
              icon: Icons.stars_rounded,
            ),
          ),
        ),
      if (m.status != MissionStatus.pending)
        AppButton(
          label: 'Signaler ce prestataire',
          icon: Icons.flag_outlined,
          variant: AppButtonVariant.text,
          onPressed: () => showReportProviderSheet(
            context,
            providerId: m.providerId,
            missionId: m.id,
          ),
        ),
    ];
  }
}

class _Etapes extends StatelessWidget {
  const _Etapes({required this.status});
  final MissionStatus status;

  // ✅ CORRECTION 3 : 2ᵉ `final scheme` SUPPRIMÉ (doublon)
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const labels = [
      'Demande envoyée',
      'Dépanneur en route',
      'Dépanneur arrivé',
      'Réparation en cours',
      'Terminé',
    ];
    final current = switch (status) {
      MissionStatus.pending => 0,
      MissionStatus.accepted => 1,
      MissionStatus.arrived => 2,
      MissionStatus.working => 3,
      MissionStatus.completed => 4,
      _ => -1,
    };

    return SoftCard(
      child: Column(
        children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    i <= current
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: i <= current
                        ? scheme.secondary
                        : scheme.onSurface.withValues(alpha: 0.35),
                    size: 28,
                  ),
                  const SizedBox(width: 14),
                  Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: i == current
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
