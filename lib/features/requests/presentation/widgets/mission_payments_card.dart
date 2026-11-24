import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/utils/travel_fee.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/requests/data/mission_service.dart';
import 'package:montotem/features/requests/domain/mission_model.dart';
import 'package:montotem/features/requests/domain/mission_payment_model.dart';
import 'package:montotem/features/requests/presentation/widgets/mission_payment_sheet.dart';

/// Paiements d'une mission. Le client déclare, le prestataire confirme ou refuse.
/// Se met à jour en direct.
class MissionPaymentsCard extends StatefulWidget {
  const MissionPaymentsCard({
    super.key,
    required this.mission,
    required this.asClient,
  });

  final Mission mission;
  final bool asClient;

  @override
  State<MissionPaymentsCard> createState() => _MissionPaymentsCardState();
}

class _MissionPaymentsCardState extends State<MissionPaymentsCard> {
  final MissionService _service = MissionService();
  RealtimeChannel? _canal;
  List<MissionPayment> _paiements = [];
  bool _loading = true;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _charger();
    _canal = _service.ecouterPaiements(widget.mission.id, () {
      if (mounted) _charger(silencieux: true);
    });
  }

  @override
  void dispose() {
    final c = _canal;
    if (c != null) _service.arreter(c);
    super.dispose();
  }

  Future<void> _charger({bool silencieux = false}) async {
    try {
      final data = await _service.paiements(widget.mission.id);
      if (mounted) setState(() => _paiements = data);
    } on MissionException {
      // Affichage conservé : la prochaine mise à jour réessaiera.
    } finally {
      if (mounted && !silencieux) setState(() => _loading = false);
      if (mounted && silencieux) setState(() => _loading = false);
    }
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  MissionPayment? _actif(String kind) {
    for (final p in _paiements) {
      if (p.kind == kind && p.status != PaymentStatus.refuse) return p;
    }
    return null;
  }

  MissionPayment? _dernierRefus(String kind) {
    MissionPayment? r;
    for (final p in _paiements) {
      if (p.kind == kind && p.status == PaymentStatus.refuse) r = p;
    }
    return r;
  }

  Future<void> _payer(String kind, int montant) async {
    final ok = await showMissionPaymentSheet(
      context,
      mission: widget.mission,
      kind: kind,
      montant: montant,
    );
    if (ok == true && mounted) _charger(silencieux: true);
  }

  Future<void> _agir(String id, Future<void> Function() action) async {
    setState(() => _busyId = id);
    try {
      await action();
      await _charger(silencieux: true);
    } on MissionException catch (e) {
      if (mounted) _msg(e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _confirmer(MissionPayment p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Argent bien reçu ?'),
        content: Text(
          p.methode.mobileMoney
              ? 'Vérifiez dans votre application ${p.methode.libelle} que '
                    '${TravelFee.fcfa(p.amountFcfa)} sont bien arrivés '
                    '(référence ${p.reference ?? '-'}).'
              : 'Confirmez que vous avez reçu ${TravelFee.fcfa(p.amountFcfa)} en espèces.',
          style: const TextStyle(fontSize: 16, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Pas encore'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Oui, confirmer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _agir(p.id, () => _service.confirmerPaiement(p.id));
  }

  Future<void> _refuser(MissionPayment p) async {
    final controller = TextEditingController();
    final motif = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paiement non reçu'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          style: const TextStyle(fontSize: 16),
          decoration: const InputDecoration(
            labelText: 'Motif (envoyé au client)',
            hintText: 'Ex. : montant non arrivé',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (motif == null || !mounted) return;
    if (motif.length < 3) {
      _msg('Indiquez un motif.');
      return;
    }
    await _agir(p.id, () => _service.refuserPaiement(p.id, motif));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return const SoftCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }
    final m = widget.mission;

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ligneTotal('Total', m.totalFcfa),
          _ligneTotal('Déjà payé', m.paidFcfa, couleur: scheme.secondary),
          _ligneTotal(
            'Reste à payer',
            m.resteFcfa,
            couleur: m.resteFcfa > 0 ? scheme.tertiary : null,
          ),
          Divider(height: 24, color: scheme.onSurface.withValues(alpha: 0.12)),
          _bloc(
            'trajet',
            'Frais de déplacement',
            m.travelFeeFcfa,
            eligible: true,
          ),
          if (m.repairFeeFcfa > 0 || m.status == MissionStatus.completed)
            _bloc(
              'reparation',
              'Réparation',
              m.repairFeeFcfa,
              eligible: m.status == MissionStatus.completed,
            ),
        ],
      ),
    );
  }

  Widget _ligneTotal(String label, int montant, {Color? couleur}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
          Text(
            TravelFee.fcfa(montant),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: couleur,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bloc(
    String kind,
    String titre,
    int montant, {
    required bool eligible,
  }) {
    if (montant <= 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          '$titre : prix non indiqué par le prestataire.',
          style: const TextStyle(fontSize: 15),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.8);
    final actif = _actif(kind);
    final refus = _dernierRefus(kind);
    final enfants = <Widget>[
      Row(
        children: [
          Expanded(
            child: Text(
              titre,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            TravelFee.fcfa(montant),
            style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ];

    if (actif == null) {
      if (refus != null) {
        enfants.add(
          Text(
            'Paiement refusé : ${refus.rejectReason ?? 'non reçu'}',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: scheme.error,
            ),
          ),
        );
      }
      if (!eligible) {
        enfants.add(
          Text(
            'Disponible à la fin du travail.',
            style: TextStyle(fontSize: 15, color: muted),
          ),
        );
      } else if (widget.asClient) {
        enfants.add(
          AppButton(
            label: 'Payer ${TravelFee.fcfa(montant)}',
            icon: Icons.payments_rounded,
            onPressed: () => _payer(kind, montant),
          ),
        );
      } else {
        enfants.add(
          Text(
            'En attente du paiement du client.',
            style: TextStyle(fontSize: 15, color: muted),
          ),
        );
      }
    } else {
      final detail = actif.methode.mobileMoney
          ? '${actif.methode.libelle} · ${actif.payerPhone} · réf. ${actif.reference ?? '-'}'
          : actif.methode.libelle;
      enfants.add(
        Align(
          alignment: Alignment.centerLeft,
          child: actif.status == PaymentStatus.confirme
              ? StatusPill(
                  label: 'Confirmé',
                  color: scheme.secondary,
                  icon: Icons.check_circle_rounded,
                )
              : StatusPill(
                  label: 'En attente de confirmation',
                  color: scheme.tertiary,
                  icon: Icons.hourglass_top_rounded,
                ),
        ),
      );
      enfants.add(Text(detail, style: TextStyle(fontSize: 14.5, color: muted)));

      if (actif.status == PaymentStatus.enAttente && !widget.asClient) {
        enfants.add(
          _busyId == actif.id
              ? const Center(child: CircularProgressIndicator())
              : Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Non reçu',
                        variant: AppButtonVariant.secondary,
                        onPressed: () => _refuser(actif),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        label: 'J\'ai reçu',
                        icon: Icons.check_rounded,
                        onPressed: () => _confirmer(actif),
                      ),
                    ),
                  ],
                ),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < enfants.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            enfants[i],
          ],
        ],
      ),
    );
  }
}
